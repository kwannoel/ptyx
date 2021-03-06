{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}

{-|
Description: The type of integers

A subtype of 'Int' is a (finite) union of intervals
-}
module Types.Intervals (
  T,
  bounded, infiniteL, infiniteR
  )
where

import           Types.SetTheoretic

import           Data.List (intercalate)
import qualified Text.ShowM as ShowM

data Bound = Finite Integer
           | PosInfinity
           | NegInfinity
           deriving (Eq)

instance Show Bound where
  show (Finite x)  = show x
  show PosInfinity = "+∞"
  show NegInfinity = "-∞"

instance Ord Bound where
  compare (Finite i1) (Finite i2) = compare i1 i2
  compare NegInfinity NegInfinity = EQ
  compare PosInfinity PosInfinity = EQ
  compare NegInfinity _ = LT
  compare _ NegInfinity = GT
  compare PosInfinity _ = GT
  compare _ PosInfinity = LT

data Elt = Elt Bound Bound deriving (Eq, Ord)
         -- Invariants: e = Elt b1 b2 => b1 <= b2
         --                              b1 /= PosInfinity
         --                              b2 /= NegInfinity

instance Show Elt where
  show (Elt NegInfinity PosInfinity) = "Int"
  show (Elt minElt maxElt)
    | minElt == maxElt = show minElt
    | otherwise  = show minElt ++ " -- " ++ show maxElt

-- | The type of intervals
newtype T = Intervals [Elt] deriving (Eq, Ord)

instance Show T where
  show (Intervals []) = "⊥"
  show (Intervals elts) =
    intercalate " | " $ map show elts

-- | Constructs a bounded interval
bounded :: Integer -> Integer -> T
bounded x y =
  if y < x then
    Intervals []
  else Intervals [ Elt (Finite x) (Finite y) ]

-- | Constructs a semi-infinite on the right interval
infiniteR :: Integer -> T
infiniteR x = Intervals [ Elt (Finite x) PosInfinity ]

-- | Constructs a semi-infinite on the left interval
infiniteL :: Integer -> T
infiniteL x = Intervals [ Elt NegInfinity (Finite x) ]

instance SetTheoretic_ T where
  empty = Intervals []

  full = Intervals [ Elt NegInfinity PosInfinity ]

  cup (Intervals i1) (Intervals i2) =
    Intervals $ foldl cup_t_atom i1 i2

    where
      cup_atom (Elt b1 t1) (Elt b2 t2) = Elt (min b1 b2) (max t1 t2)
      cup_t_atom [] a = [a]
      cup_t_atom t atm
        | b'2 < b1 = atm : t
        | b'1 > b2 = Elt b1 b2 : cup_t_atom tl atm
        | otherwise = cup_t_atom tl (cup_atom (Elt b1 b2) (Elt b'1 b'2))
        where
          Elt b1 b2:tl = t
          Elt b'1 b'2 = atm

  cap (Intervals i1) (Intervals i2) =
    Intervals (i2 >>= cap_t_atom i1)

    where
      cap_atom (Elt b1 t1) (Elt b2 t2) = Elt (max b1 b2) (min t1 t2)
      cap_t_atom [] _ = []
      cap_t_atom t atm
        | t2 < b1 = []
        | b2 > t1 = cap_t_atom tl atm
        | otherwise = cap_atom (Elt b1 t1) (Elt b2 t2):tl
        where
          Elt b1 t1:tl = t
          Elt b2 t2 = atm


  neg (Intervals i) = Intervals $ neg' NegInfinity i
    where
      neg' lastBound []
        | lastBound == PosInfinity = []
        | otherwise = [ Elt lastBound PosInfinity ]
      neg' lastBound (Elt x y:tl)
        | lastBound == x = neg' y tl -- Should only occur
                                    -- if x == lastBound == NegInfinity
        | otherwise =
          case y of
            Finite nb ->
              case x of
                Finite nb' ->
                  Elt lastBound (Finite $ nb'-1) : neg' (Finite $ nb+1) tl
                NegInfinity -> undefined
                  -- impossible because lastBound < x
                PosInfinity -> undefined
                  -- impossible because x is the lower bound of an interval
            PosInfinity -> [Elt lastBound x]
            NegInfinity -> undefined
              -- This shouldn't happen : y can't be NegInfinity as
              -- it is the upper bound of an interval

  diff i1 i2 = cap i1 (neg i2)

instance SetTheoretic Applicative T where
  isEmpty (Intervals l) = pure $ null l

instance Monad m => ShowM.ShowM m T where
  showM = ShowM.fromShow
