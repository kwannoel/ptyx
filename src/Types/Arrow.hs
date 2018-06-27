{-|
Description: Arrow types
-}

{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE UndecidableInstances #-}

module Types.Arrow (
  T(..), Arrow(..),
  domain, codomain, atom,
  getApplication,
  compDomain,
  get,
  decompose
  )
where

import qualified Types.Node as Node
import           Types.SetTheoretic

import qualified Control.Monad.Memo as Memo
import qualified Data.Bool.Applicative as ABool
import           Data.Semigroup ((<>))
import qualified Data.Set as Set
import qualified Data.Text.Lazy as T
import qualified Text.ShowM as ShowM
import qualified Types.Bdd as Bdd

-- | Atomic arrow type
data Arrow t = Arrow t t deriving (Eq, Ord)

instance ShowM.ShowM m t => ShowM.ShowM m (Arrow t) where
  showM (Arrow t1 t2) = do
    prettyT1 <- ShowM.showM t1
    prettyT2 <- ShowM.showM t2
    pure $ "(" <> prettyT1 <> ") -> " <> prettyT2

instance ShowM.ShowM Memo.T t => Show (Arrow t) where
  show = T.unpack . Memo.runEmpty . ShowM.showM

-- | Arrow type
newtype T t = T (Bdd.T (Arrow t)) deriving (Eq, Ord, SetTheoretic_)

instance ShowM.ShowM m t => ShowM.ShowM m (T t) where
  showM (T x) = do
    prettyX <- ShowM.showM x
    case prettyX of
      "⊥" -> pure "⊥"
      tt -> pure $ "(" <> tt <> ") & (⊥ -> ⊤)"

-- | Returns the domain of an atomic arrow type
domain :: Arrow t -> t
domain (Arrow d _) = d

-- | Returns the codomain of an atomic arrow type
codomain :: Arrow t -> t
codomain (Arrow _ c) = c

-- | Builds an atomic arrow type
atom :: t -> t -> T t
atom dom codom = T (Bdd.atom $ Arrow dom codom)

isEmptyA :: SetTheoretic t => T t -> Memo.T Bool
isEmptyA (T a)
  | Bdd.isTriviallyEmpty a = pure True
  | Bdd.isTriviallyFull a = pure False
  | otherwise =
    let arrow = Bdd.toDNF a in
    ABool.all emptyIntersect arrow

    where
      emptyIntersect (posAtom, negAtom) =
        ABool.any (sub' posAtom) negAtom

      sub' p (Arrow t1 t2) =
        subCupDomains t1 p ABool.&&
        superCapCodomains t2 p ABool.&&
        forallStrictSubset
          (\subset comp -> subCupDomains t1 subset ABool.|| superCapCodomains t1 comp)
          p

      subCupDomains t p =
        t `sub` cupN (Set.map domain p)

      superCapCodomains t p =
        capN (Set.map codomain p) `sub` t


instance SetTheoretic t => SetTheoretic (T t) where
  isEmpty = isEmptyA

-- | @getApplication arr s@ returns the biggest type @t@ such
-- that @s -> t <: arr@
getApplication :: forall t c m.
  SetTheoretic t => Bdd.DNF (Arrow t) -> t -> Memo.T t
getApplication arr s =
  cupN <$> mapM elemApp (Set.toList arr)
  where
    elemApp :: (Set.Set (Arrow t), Set.Set (Arrow t)) -> Memo.T t
    elemApp (pos, _) =
      foldStrictSubsets (pure empty) addElemApp pos Set.empty
    addElemApp :: Memo.T t -> Set.Set (Arrow t) -> Set.Set (Arrow t) -> Memo.T t
    addElemApp accM subset compl = do
      acc <- accM
      isInDomains <- s `sub` cupN (Set.map domain subset)
      pure $
        if isInDomains
        then acc
        else acc `cup` capN (Set.map codomain compl)

-- | Get the domain of a composed arrow
compDomain :: forall t. SetTheoretic_ t => Bdd.DNF (Arrow t) -> t
compDomain = capN . Set.map (cupN . Set.map domain . fst)

-- This is used for the checking of lambdas
decompose :: forall t. SetTheoretic_ t => Bdd.DNF (Arrow t) -> Set.Set (Arrow t)
decompose = foldl (\accu (pos, _) -> squareUnion accu pos) (Set.singleton (Arrow full empty))
  where
    squareUnion :: Set.Set (Arrow t) -> Set.Set (Arrow t) -> Set.Set (Arrow t)
    squareUnion iSet jSet =
      foldr mappend mempty $ Set.map
        (\(Arrow si ti) -> Set.map
          (\(Arrow sj tj) -> Arrow (si `cap` sj) (ti `cup` tj))
          jSet)
        iSet

get :: Ord t => T t -> Bdd.DNF (Arrow t)
get (T bdd) = Bdd.toDNF bdd
