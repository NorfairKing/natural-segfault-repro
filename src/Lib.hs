module Lib where

import Data.GenValidity
import Data.GenValidity.Mergeful
import Data.Mergeful
import Data.Mergeful.Timed
import Numeric.Natural
import Test.QuickCheck

someFunc :: IO ()
someFunc = do
  sample (genValid :: Gen Natural)
  sample (genValid :: Gen ServerTime)
  sample (genValid :: Gen (Timed Int))
