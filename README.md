## Preliminary data:

Upgrades to validity: be40c0a0b0bf6a1d58f4a6a5c6770c4a544c4450

- better generators for
  - Int, Int8, Int16, Int32, Int64
  - Word, Word8, Word16, Word32, Word64
  - Float, Double
  - Integer, Natural

Upgrades to mergeful: f1c780066a6279cf5b4a4531df0a5ee4eab78c6a

- ServerTime now uses Natural instead of Word64


## Current ploblem

On Nixos, on `31665c6` in the smos repo: (https://github.com/NorfairKing/smos)

stack test :smos-server-test segfaults:

```
smos-server-gen> Test suite smos-server-test failed
Test suite failure for package smos-server-gen-0.0.0.0
    smos-server-test:  exited with: ExitFailure (-11)
```

nix-build -A smos-server-gen does not segfault but still fails:

```
Failures:

  test/Smos/Server/EnvSpec.hs:37:5:
  1) Smos.Server.Env.writeServerStore can read exactly what was just written
       uncaught exception: ArithException
       arithmetic underflow
```


### Digging

stack ghci smos-server-gen --no-load --package genvalidity --package genvalidity-mergeful

This works:

```
import Test.QuickCheck
import Data.GenValidity
import Numeric.Natural
import Data.Mergeful.Timed
sample (genUnchecked :: Gen Natural)
sample (genValid :: Gen Natural)
import Data.Mergeful.Timed
import Data.GenValidity.Mergeful
sample (genUnchecked :: Gen ServerTime)
sample (genValid :: Gen ServerTime)
```

This doesn't:

```
sample (genUnchecked :: Gen (Timed Int))
Timed {timedValue = -8382519431551690709, timedTime = ServerTime {unServerTime = /tmp/nix-shell-15284-0/rc: line 1: 16043 Segmentation fault      (core dumped) '/nix/store/7xvxx52qrqgksycj88f5fq6hcifq92c8-stack-2.1.3.1/bin/stack' $STACK_IN_NIX_EXTRA_ARGS '--internal-re-exec-version=2.1.3.1' 'ghci' 'smos-server-gen' '--no-load' '--package' 'genvalidity' '--package' 'genvalidity-mergefu
```

The same happens with `genValid :: Gen (Timed Int)`.

Note:

``` haskell
data Timed a =
  Timed
    { timedValue :: !a
    , timedTime :: !ServerTime
    }
instance Validity a => Validity (Timed a)

instance GenUnchecked a => GenUnchecked (Timed a)

instance GenValid a => GenValid (Timed a) where
  genValid = genValidStructurallyWithoutExtraChecking
  shrinkValid = shrinkValidStructurallyWithoutExtraFiltering

instance GenUnchecked ServerTime

instance GenValid ServerTime where
  genValid = genValidStructurallyWithoutExtraChecking
  shrinkValid = shrinkValidStructurallyWithoutExtraFiltering
```


#### GDB

I tried using GDB:

```
$ gdb ./smos-server-gen/.stack-work/dist/x86_64-linux-nix/Cabal-2.4.0.1/build/smos-server-test/smos-server-test
(gdb) run
[...]
Thread 16 "smos-server-t:w" received signal SIGSEGV, Segmentation fault.
(gdb) bt
#0  0x0000000001e6e1a4 in base_GHCziNatural_naturalToInteger_info ()
#1  0x0000000000000000 in ?? ()
```


I found the code for that function: (https://github.com/ghc/ghc/blob/8dd9929ad29fd200405d068463af64dafff6b402/libraries/base/GHC/Natural.hs#L241-L244)

``` haskell
-- | @since 4.12.0.0
naturalToInteger :: Natural -> Integer
naturalToInteger (NatS# w)  = wordToInteger w
naturalToInteger (NatJ# bn) = Jp# bn
{-# CONSTANT_FOLDED naturalToInteger #-}
```

Note that `CONSTANT_FOLDED` is just `NOINLINE`. (https://downloads.haskell.org/~ghc/latest/docs/html/libraries/integer-gmp-1.0.2.0/src/GHC-Integer-Type.html)

I don't understand why this would be called.
Indeed, if you look at the generator for Natural values, you would expect things to go the other way:

``` haskell
instance GenUnchecked Integer where
    genUnchecked = genInteger
    shrinkUnchecked = shrink

instance GenValid Integer

#if MIN_VERSION_base(4,8,0)
instance GenUnchecked Natural where
    genUnchecked = fromInteger . abs <$> genUnchecked
    shrinkUnchecked = fmap (fromInteger . abs) . shrinkUnchecked . toInteger

instance GenValid Natural where
    genValid = fromInteger . abs <$> genValid
#endif

genInteger :: Gen Integer
genInteger = sized $ \s -> oneof $
  (if s >= 10 then (genBiggerInteger :) else id)
    [ genIntSizedInteger
    , small
    ]
  where
    small = sized $ \s ->  choose (- toInteger s, toInteger s)
    genIntSizedInteger = toInteger <$> (genIntX :: Gen Int)
    genBiggerInteger = sized $ \s ->do
      (a, b, c) <- genSplit3 s
      ai <- resize a genIntSizedInteger
      bi <- resize b genInteger
      ci <- resize c genIntSizedInteger
      pure $ ai * bi + ci
```

### Minimal repro

I'm trying to make a minimal reproducible example of what goes wrong, but the problem does not occur in this repository.
Neither as an executable nor as a test suite.


### Dynamically linked libgmp version

I already checked, the dynamically linked libgmp libraries are the same when building with stack vs nix.

```
$ nix-build --keep-failed default.nix -A smos-server-gen

$ ldd /tmp/nix-build-smos-server-gen-0.0.0.0.drv-1/source/dist/build/smos-server-test/smos-server-test
	linux-vdso.so.1 (0x00007ffdd9df2000)
	libm.so.6 => /nix/store/6yaj6n8l925xxfbcd65gzqx3dz7idrnn-glibc-2.27/lib/libm.so.6 (0x00007fc6fd6ce000)
	libpthread.so.0 => /nix/store/6yaj6n8l925xxfbcd65gzqx3dz7idrnn-glibc-2.27/lib/libpthread.so.0 (0x00007fc6fd6ad000)
	libsqlite3.so.0 => /nix/store/isg5d6rh4zdva16hxs7qg6k1s96v39mx-sqlite-3.28.0/lib/libsqlite3.so.0 (0x00007fc6fd595000)
	libz.so.1 => /nix/store/62ar9xmrlcnlgmwgfi77xz6bq1180vhi-zlib-1.2.11/lib/libz.so.1 (0x00007fc6fd576000)
	librt.so.1 => /nix/store/6yaj6n8l925xxfbcd65gzqx3dz7idrnn-glibc-2.27/lib/librt.so.1 (0x00007fc6fd56a000)
	libutil.so.1 => /nix/store/6yaj6n8l925xxfbcd65gzqx3dz7idrnn-glibc-2.27/lib/libutil.so.1 (0x00007fc6fd565000)
	libdl.so.2 => /nix/store/6yaj6n8l925xxfbcd65gzqx3dz7idrnn-glibc-2.27/lib/libdl.so.2 (0x00007fc6fd560000)
	libgmp.so.10 => /nix/store/j2p1qjbajqfb95ba3dqgjbsknipknikk-gmp-6.1.2/lib/libgmp.so.10 (0x00007fc6fd4ca000)
	libffi.so.6 => /nix/store/z39757pg1gp5lgkxcn0yv6nv4lgmpnad-libffi-3.2.1/lib/libffi.so.6 (0x00007fc6fd4be000)
	libc.so.6 => /nix/store/6yaj6n8l925xxfbcd65gzqx3dz7idrnn-glibc-2.27/lib/libc.so.6 (0x00007fc6fd308000)
	/nix/store/6yaj6n8l925xxfbcd65gzqx3dz7idrnn-glibc-2.27/lib/ld-linux-x86-64.so.2 => /nix/store/y9zg6ryffgc5c9y67fcmfdkyyiivjzpj-glibc-2.27/lib64/ld-linux-x86-64.so.2 (0x00007fc6fd866000)
```


```
$ ldd ./smos-server-gen/.stack-work/dist/x86_64-linux-nix/Cabal-2.4.0.1/build/smos-server-test/smos-server-test
	linux-vdso.so.1 (0x00007ffc967e4000)
	libm.so.6 => /nix/store/6yaj6n8l925xxfbcd65gzqx3dz7idrnn-glibc-2.27/lib/libm.so.6 (0x00007f157ed10000)
	libpthread.so.0 => /nix/store/6yaj6n8l925xxfbcd65gzqx3dz7idrnn-glibc-2.27/lib/libpthread.so.0 (0x00007f157ecef000)
	libz.so.1 => /nix/store/62ar9xmrlcnlgmwgfi77xz6bq1180vhi-zlib-1.2.11/lib/libz.so.1 (0x00007f157ecd0000)
	librt.so.1 => /nix/store/6yaj6n8l925xxfbcd65gzqx3dz7idrnn-glibc-2.27/lib/librt.so.1 (0x00007f157ecc6000)
	libutil.so.1 => /nix/store/6yaj6n8l925xxfbcd65gzqx3dz7idrnn-glibc-2.27/lib/libutil.so.1 (0x00007f157ecc1000)
	libdl.so.2 => /nix/store/6yaj6n8l925xxfbcd65gzqx3dz7idrnn-glibc-2.27/lib/libdl.so.2 (0x00007f157ecba000)
	libgmp.so.10 => /nix/store/j2p1qjbajqfb95ba3dqgjbsknipknikk-gmp-6.1.2/lib/libgmp.so.10 (0x00007f157ec24000)
	libffi.so.6 => /nix/store/z39757pg1gp5lgkxcn0yv6nv4lgmpnad-libffi-3.2.1/lib/libffi.so.6 (0x00007f157ec18000)
	libc.so.6 => /nix/store/6yaj6n8l925xxfbcd65gzqx3dz7idrnn-glibc-2.27/lib/libc.so.6 (0x00007f157ea62000)
	/nix/store/6yaj6n8l925xxfbcd65gzqx3dz7idrnn-glibc-2.27/lib/ld-linux-x86-64.so.2 => /nix/store/y9zg6ryffgc5c9y67fcmfdkyyiivjzpj-glibc-2.27/lib64/ld-linux-x86-64.so.2 (0x00007f157eea8000)
```


## LTS upgrade

Upgrading to lts-14.25 gets rid of the segfault, but it's the same ghc version!
