{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
module Hledger.Components.MainComponent where

import           Control.Lens hiding (children)
import           Data.Accounting.Journal (Journal)
import           Data.Semigroup ((<>))
import           Data.Text (Text) 
import           Hledger.Components.JournalComponent (journalComponent)
import           Hledger.Components.JournalLoader (journalLoader)
import           Hledger.Components.Utils (addClassName)
import           VirtualHom.Element 
import qualified VirtualHom.Html as H 
import           VirtualHom.Components


newtype AppProps = AppProps { _getProps :: Either Text (Maybe Journal) }
makeLenses ''AppProps

initialProps :: AppProps
initialProps = AppProps $ Right Nothing

data AppState = AppState {
  _journalComp :: Component AppProps,
  _loadingComp :: Component AppProps 
}
makeLenses ''AppState

appState :: AppState
appState = AppState j l where
  j = specialise getProps $ on (_Right . _Just) journalComponent
  l = specialise getProps $ on _Right journalLoader

mainComponent :: Component AppProps
mainComponent = component appState $ \t ->
  [ H.div 
      & addClassName "top-menu"
      & children .~ [
        H.div & addClassName "title" & content .~ "HLedger Dashboard"],
    H.div
      & addClassName "main-area"
      & children .~ (
        subComponent props (state.loadingComp) t <>
        subComponent props (state.journalComp) t)
  ]