{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE FlexibleContexts #-}
module Data.Accounting.Currency(
  Currency(..),
  -- * Constructors
  empty,
  currency,
  -- * Operations
  add,
  scale,
  plus,
  invert,
  toList,
  -- * Parser
  balancingCurrencyP
) where

import           Control.Applicative hiding (empty, optional)
import           Control.Lens hiding ((...), singular)
import           Control.Monad.State
import           Data.AdditiveGroup
import           Data.Char (isDigit, isPrint, isSpace)
import           Data.List (intercalate)
import           Data.Monoid
import qualified Data.Map.Strict as M
import           Data.Ratio
import           Data.Semigroup hiding (option)
import           Data.Text (Text)
import qualified Data.Text as T
import           Data.VectorSpace
import           Text.Parsec hiding ((<|>), many)
import           Text.Parsec.Combinator
import           Text.Parsec.Text
import           Text.Read (readEither)

import Data.Accounting.ParsingState

-- | Values with currencies.
newtype Currency a = Currency { _values :: M.Map a Rational }
  deriving (Eq, Ord)

makeLenses ''Currency

nonZero :: Ord a => M.Map a Rational -> M.Map a Rational
nonZero = M.filter (not . (==) 0)

mapCurrencies :: Ord b => (a -> b) -> Currency a -> Currency b
mapCurrencies f = Currency . M.mapKeys f . view values

-- $setup
-- >>> import Control.Applicative hiding (empty)
-- >>> import Control.Monad.State
-- >>> import Text.Parsec.Text
-- >>> import Text.Parsec.Prim
-- >>> import Data.Text (Text)
-- >>> import qualified Data.Text as T
-- >>> :set -XScopedTypeVariables
-- >>> :set -XFlexibleInstances
-- >>> :set -XOverloadedStrings
-- >>> let parseOnly p s = evalState (runParserT p () "" (T.pack s)) defaultParsingState

instance Ord a => Semigroup (Currency a) where
  (<>) = mappend

-- | `Currency` is a `Monoid` where `<>` is `plus` and `mempty` is `empty`
instance Ord a => Monoid (Currency a) where
  mempty = empty
  mappend = plus

-- | `Currency` is an `AdditiveGroup` where `zeroV` and `^+^` are the monoid
--   operations and `negateV` is `invert`
instance Ord a => AdditiveGroup (Currency a) where
  zeroV = empty
  (^+^) = plus
  negateV = invert

instance (Ord a, Show a) => Show (Currency a) where
  show = show . toList

-- | `Currency` is a `VectorSpace` with `scale`
instance Ord a => VectorSpace (Currency a) where
  type Scalar (Currency a) = Rational
  (*^) = scale

-- | Create a `Currency` with a single value
--
-- >>> currency 1 "EUR"
-- [("EUR",1 % 1)]
currency :: Rational -> Text -> Currency Text
currency r = Currency . nonZero . flip M.singleton r

-- | Add an amount to a `Currency`
--
-- >>> add 1 "EUR" $ currency 1 "EUR"
-- [("EUR",2 % 1)]
-- >>> add 1 "GBP" $ currency 1 "EUR"
-- [("EUR",1 % 1),("GBP",1 % 1)]
-- >>> add (-1) "GBP" $ currency 1 "GBP"
-- []
add :: Ord a => Rational -> a -> Currency a -> Currency a
add r s = Currency . nonZero . M.insertWith (+) s r . view values

-- | Scale a currency by a factor
--
-- >>> scale 2 $ currency 1 "EUR"
-- [("EUR",2 % 1)]
-- >>> scale 2.5 $ add 1 "GBP" $ currency 5 "EUR"
-- [("EUR",25 % 2),("GBP",5 % 2)]
-- >>> scale 0 $ currency 1 "EUR"
-- []
scale :: Ord a => Rational -> Currency a -> Currency a
scale f = Currency . nonZero . M.map ((*) f) . view values

-- | Empty `Currency` with no values.
--
-- >>> empty
-- []
empty :: Currency a
empty = Currency M.empty

-- | Combine two `Currency`s by adding their values.
plus :: Ord a => Currency a -> Currency a -> Currency a
plus l r = Currency $ nonZero $ M.unionWith (+) (l^.values) (r^.values)

-- | Invert the values of a `Currency` by multiplying them with -1.
invert :: Ord a => Currency a -> Currency a
invert = Currency . fmap negate . view values

-- | Get a list of the values in this `Currency`
toList :: Ord a => Currency a -> [(a, Rational)]
toList = M.toList . view values

-- | Parse a `Currency` from `Text`. The return value has a single
-- currency-amount pair. If no currency amount is found, then the currency will
-- be `Nothing`.
-- >>> parseOnly singleCurrencyP "1 EUR"
-- Right [(Just "EUR",1 % 1)]
-- >>> parseOnly singleCurrencyP "0.5"
-- Right [(Nothing,1 % 2)]
-- >>> parseOnly singleCurrencyP "GBP 12.0"
-- Right [(Just "GBP",12 % 1)]
-- >>> parseOnly singleCurrencyP "GBP38.11"
-- Right [(Just "GBP",3811 % 100)]
singleCurrencyP :: (Monad m, MonadState (ParsingState (Currency Text)) m, Stream s m Char) => ParsecT s u m (Currency (Maybe Text))
singleCurrencyP = pr <?> "currencyP" where
  pr = (try $ fmap (mapCurrencies Just) currencyWithSymbolP) 
      <|> (noSymbolCurrencyP    <?> "noSymbolCurrencyP")
  currency' r = Currency . nonZero . flip M.singleton r
  noSymbolCurrencyP = do
    sgn <- signP
    r   <- fmap sgn $ rational
    return $ currency' r $ Nothing

-- | Parse a currency with a symbol (left or right of it)
currencyWithSymbolP :: (Monad m, MonadState (ParsingState (Currency Text)) m, Stream s m Char) => ParsecT s u m (Currency Text)
currencyWithSymbolP = pr <?> "currencyWithSymbolP" where
  pr = (try leftSymbolCurrencyP <?> "leftSymbolCurrencyP")
      <|> (rightSymbolCurrencyP  <?> "rightSymbolCurrencyP")
  currency' r = Currency . nonZero . flip M.singleton r
  leftSymbolCurrencyP  = do
    sgn <- signP <?> "sign"
    s   <- currencySymbol <?> "currency symbol"
    _  <- many (satisfy isSpace) <?> "space"
    sgn2 <- signP <?> "sign 2"
    amt <- fmap (sgn2 . sgn) $ (rational <?> "rational")
    return $ currency' amt s
  rightSymbolCurrencyP = do
    amt <- rational
    _   <- many (satisfy isSpace)
    s   <- currencySymbol
    return $ currency' amt s

-- | Currency separator ('@@')
currencySeparator :: (Monad m, Stream s m Char) => ParsecT s u m ()
currencySeparator = fmap (const ()) $ char '@' >> char '@' 

-- | Two currencies separated by an '@@'.
currencyWithExchangeRateP :: (Monad m, MonadState (ParsingState (Currency Text)) m, Stream s m Char) => ParsecT s u m (Currency Text)
currencyWithExchangeRateP = do
  first <- currencyWithSymbolP
  _ <- many (satisfy isSpace) <?> "space"
  _ <- currencySeparator <?> "currency separator (@@)"
  _   <- many (satisfy isSpace) <?> "space"
  second <- currencyWithSymbolP
  _ <- runningTotal <>= second
  return first

-- | Parse a `Currency` from `Text`, optionally followed by its equivalend in 
-- another currency (separated by '@@').
currencyP :: (Monad m, MonadState (ParsingState (Currency Text)) m, Stream s m Char) => ParsecT s u m (Currency Text)
currencyP = (try currencyWithExchangeRateP <?> "currencyWithExchangeRateP") <|> (defaultCurrencyP <?> "defaultCurrencyP")

-- | Parse a `Currency`. If only a number but no symbol is found, the last known
-- symbol will be used.
--
-- >>> parseOnly defaultCurrencyP "-10.0"
-- Right [("",(-10) % 1)]
defaultCurrencyP :: (Monad m, MonadState (ParsingState (Currency Text)) m, Stream s m Char) => ParsecT s u m (Currency Text)
defaultCurrencyP = (gets $ view lastCurrencySymbol) >>= \c -> do
  let applyDefault = mapCurrencies (maybe c id)
  r <- fmap applyDefault singleCurrencyP
  _ <- runningTotal <>= r
  return r

-- | Parse a `Currency`. If no number is found, the `ParsingState`'s
-- `runningTotal` will be used to balance the transaction.
balancingCurrencyP :: (Monad m, MonadState (ParsingState (Currency Text)) m, Stream s m Char) => ParsecT s u m (Currency Text)
balancingCurrencyP = (gets $ view runningTotal) >>= \old -> do
  option (negateV old) currencyP

-- | Parse a currency symbol
currencySymbol :: (Monad m, MonadState (ParsingState a) m, Stream s m Char) => ParsecT s u m Text
currencySymbol = do
  let cond c = isPrint c && (not $ isSpace c) && (not $ isDigit c) && (not $ c `elem` "+-")
  let p = many1 (satisfy cond) <?> "currency symbol"
  result <- fmap T.pack p
  _  <- lastCurrencySymbol .= result
  return result

-- | Parse a sign (+/-) to a function,  `id` for optional '+' and `negate`
--   for '-'
signP :: (Monad m, Stream s m Char) => ParsecT s u m (Rational -> Rational)
signP = try m <|> p where
  m = char '-' >> return negate
  p = option id $ char '+' >> return id

-- | Parse a rational number
--
-- TODO: Move to Utils module?
rational :: (Stream s m Char, Monad m) => ParsecT s u m Rational
rational = do
  s <- signP
  before <- many digit
  _ <- optional $ char '.'
  after <- many digit
  case (before ++ after) of
    [] -> fail "rational"
    ds -> either fail (return . s . flip (%) (10^(length after))) (readEither ds :: Either String Integer)
