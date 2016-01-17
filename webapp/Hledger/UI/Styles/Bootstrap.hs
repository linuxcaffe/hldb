{- Bootstrap styles -}
{-# LANGUAGE OverloadedStrings #-}
module Hledger.UI.Styles.Bootstrap where

import           Control.Lens
import           Data.Map (Map)
import qualified Data.Map as M
import           Prelude hiding (div)

import Hledger.UI.Element

container :: Elem m ()
container = div & attributes . at "class" ?~ "container"

row :: Elem m ()
row = div & attributes . at "class" ?~ "row"

btnDefault :: Elem m ()
btnDefault = button & attributes . at "class" ?~ "btn btn-default"