{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE TemplateHaskell #-}

module NixLight.WithLoc where

import Data.Functor.Compose
import Nix.Expr (SrcSpan)
import Text.Show.Deriving

type Loc = SrcSpan

data T a = T { loc   :: SrcSpan
             , descr :: a
             }
             deriving (Eq, Ord, Show, Functor)

$(deriveShow1 ''T)

type TF f = Compose T f
