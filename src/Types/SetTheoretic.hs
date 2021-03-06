{-# LANGUAGE ApplicativeDo #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DefaultSignatures #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE MultiParamTypeClasses #-}


{-|
Description: typeclasses for set-theoretic datatypes

Provides set-theoretic connectives and related operations
-}
module Types.SetTheoretic where

import           Control.Applicative (liftA2)
import qualified Control.Monad.State as SM

-- | Typeclass for types with set-theoretic (unions, intersections, ...)
-- operations
class Ord a => SetTheoretic_ a where

  -- | The empty set
  empty :: a

  -- | The maximal set that contains all the other sets
  full :: a

  -- | Set-theoretic operations
  cup :: a -> a -> a
  cap :: a -> a -> a
  diff :: a -> a -> a
  neg :: a -> a

  -- | Infix version of the operators
  (\/) :: a -> a -> a
  (/\) :: a -> a -> a
  (\\) :: a -> a -> a

  (\/) = cup
  (/\) = cap
  (\\) = diff

  neg = diff full
  -- diff x y = x \\ neg y

-- | N-ary versions of the set-theoretic operators
cupN :: (SetTheoretic_ a, Foldable t) => t a -> a
capN :: (SetTheoretic_ a, Foldable t) => t a -> a
cupN = foldl cup empty
capN = foldl cap full

-- | SetTheoretic with tests for emptyness and containment
--
-- One may be automatically defined in term of the other
class (SetTheoretic_ a) => SetTheoretic c a | a -> c where
  isEmpty :: c m => a -> m Bool
  sub :: c m => a -> a -> m Bool

  sub x1 x2 = isEmpty $ diff x1 x2
  isEmpty x = sub x empty

  {-# MINIMAL isEmpty | sub #-}

-- | Infix version of sub
(<:) :: (SetTheoretic (SM.MonadState x) a, Monoid x) => a -> a -> Bool
a <: b = flip SM.evalState mempty $ a `sub` b

isFull :: (SetTheoretic c a, c m) => a -> m Bool
isFull x = isEmpty (full \\ x)

(~:) :: (SetTheoretic (SM.MonadState x) a, Monoid x) => a -> a -> Bool
a ~: b = flip SM.evalState mempty $ (a `sub` b) <&&> (b `sub` a)

(<&&>) :: Applicative m => m Bool -> m Bool -> m Bool
(<&&>) = liftA2 (&&)

(<||>) :: Applicative m => m Bool -> m Bool -> m Bool
(<||>) = liftA2 (||)
