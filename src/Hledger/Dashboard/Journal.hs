{-# LANGUAGE TemplateHaskell #-}
module Hledger.Dashboard.Journal where

import           Control.Lens hiding ((...), singular)
import           Data.AdditiveGroup
import           Data.Foldable
import           Data.Monoid
import qualified Data.Map.Strict as M
import           Data.Time.Calendar (
  Day,
  addDays,
  addGregorianMonthsClip,
  addGregorianYearsClip,
  fromGregorian,
  toGregorian)
import           Data.Time.Calendar.WeekDate (fromWeekDate, toWeekDate)
import           Hledger.Dashboard.Account
import           Hledger.Dashboard.Currency (Currency)
import           Numeric.Interval

data ReportingInterval = Day | Week | Month | Year
  deriving (Eq, Ord, Show, Enum, Bounded)

enumerate :: (Enum a, Bounded a) => [a]
enumerate = enumFromTo minBound maxBound

-- | Journal contains accounts for various reporting periods
data Journal = Journal {
  _intervals :: M.Map (Day, ReportingInterval) Account,
  _firstDay :: Maybe Day
}

makeLenses ''Journal

-- | Get the first day of the interval containing the given day
-- | If the interval is `Day` then `begin` and `end` both evaluate to `id`
begin :: ReportingInterval -> Day -> Day
begin i d = case i of
  Day -> d
  Week -> fromWeekDate y w 1 where
    (y, w, _) = toWeekDate d
  Month -> fromGregorian y m 1 where
    (y, m, _) = toGregorian d
  Year -> fromGregorian y 1 1 where
    (y, _, _) = toGregorian d

-- | Get the last day of the interval containing the given day
-- | If the interval is `Day` then `begin` and `end` both evaluate to `id`
end :: ReportingInterval -> Day -> Day
end i d = case i of
  Day -> d
  Week -> pred $ fromWeekDate y w 1 where
    (y, w, _) = toWeekDate d'
    d' = addDays 7 d
  Month -> pred $ fromGregorian y m 1 where
    (y, m, _) = toGregorian $ addGregorianMonthsClip 1 d
  Year -> pred $ fromGregorian y 1 1 where
    (y, _, _) = toGregorian $ addGregorianYearsClip 1 d

-- | Get all intervals starting at a given date
startingAt :: Day -> [ReportingInterval]
startingAt d = takeWhile ((==) d . flip begin d) enumerate

breakDown :: Interval Day -> [(Day, ReportingInterval)]
breakDown i = current : rest where
  f = inf i
  t = sup i
  nextStart = succ $ uncurry (flip end) current
  current = (f, maximum $ filter endsBefore $ startingAt f)
  endsBefore rpi = (end rpi f) <= t
  rest = case singular i of
    True  -> []
    False -> breakDown $ nextStart ... t

-- | Get accounts for an interval
accountsFor :: Interval Day -> Journal -> Account
accountsFor i j = fold accts where
  start = maybe fd (min fd) $ view firstDay j
  fd = inf i
  lookp t = M.findWithDefault mempty t $ view intervals j
  accts = map lookp $ breakDown i

-- | Get balance since beginning of journal
balance :: Day -> Journal -> Account
balance d j = accountsFor (start ... d) j where
  start = maybe d id $ view firstDay j