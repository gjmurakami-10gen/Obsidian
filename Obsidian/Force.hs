
{-# LANGUAGE MultiParamTypeClasses,
             FlexibleInstances,
             ScopedTypeVariables,
             TypeFamilies,
             GADTs #-} 

{- Joel Svensson 2012

   Notes:

   2012-12-10: Edited 


   TODO:
    # This is a pretty problematic module.
      Figure out how to generalise the force functions
      to things like Push arrays of pairs.. 
-}

module Obsidian.Force where


import Obsidian.Program
import Obsidian.Exp
import Obsidian.Array
import Obsidian.Types

import Data.Word
---------------------------------------------------------------------------
-- New Approach to Forceable. 
---------------------------------------------------------------------------
class Forceable a where
  type Forced a 
  write_ :: a -> BProgram (Forced a)
  force  :: a -> BProgram (Forced a)  
  
---------------------------------------------------------------------------
-- Force local
---------------------------------------------------------------------------
instance Scalar a => Forceable (Pull (Exp a)) where
  type Forced (Pull (Exp a)) = Pull (Exp a)
  write_ arr = write_ (push arr) 
  force arr = force (push arr)
  
instance Scalar a => Forceable (Push (Exp a)) where
  type Forced (Push (Exp a)) = Pull (Exp a)
  write_ (Push n p) =
    do
      -- Allocate is a bit strange since
      -- it wants the n in bytes! But also knows the type. 
      name <- BAllocate (n * fromIntegral (sizeOf (undefined :: Exp a)))
                        (Pointer (typeOf (undefined :: (Exp a))))
      p (targetArr name)
      -- BSync
      return $ Pull n (\i -> index name i)
    where
      targetArr name e i = TAssign name i e

  force p =
    do
      rval <- write_ p
      BSync
      return rval

-- Is it possible to avoid being this repetitive ? 
instance (Scalar a,Scalar b) => Forceable (Push (Exp a,Exp b)) where
  type Forced (Push (Exp a,Exp b)) = Pull (Exp a, Exp b)
  write_ (Push n p) =
    do
      -- Allocate is a bit strange since
      -- it wants the n in bytes! But also knows the type. 
      name1 <- BAllocate (n * fromIntegral (sizeOf (undefined :: Exp a)))
                         (Pointer (typeOf (undefined :: (Exp a))))
      name2 <- BAllocate (n * fromIntegral (sizeOf (undefined :: Exp b)))
                         (Pointer (typeOf (undefined :: (Exp b))))
      p (targetArr (name1,name2))
      -- BSync
      return $  Pull n (\i -> (index name1 i,
                               index name2 i))
                     
    where
      targetArr (name1,name2) (e1,e2) i = TAssign name1 i e1 >>
                                          TAssign name2 i e2

  force p =
    do
      rval <- write_ p
      BSync
      return rval


instance (Forceable a, Forceable b) => Forceable (a,b) where
  type Forced (a,b) = (Forced a, Forced b)
  write_ (a,b) =
    do
      r1 <- force a
      r2 <- force b 
      return (r1,r2)
  force p =
    do
      rval <- force p
      BSync
      return rval
