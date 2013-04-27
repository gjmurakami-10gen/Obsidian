{-# LANGUAGE FlexibleInstances,
             OverlappingInstances,
             UndecidableInstances,
             FlexibleContexts,
             MultiParamTypeClasses,
             TypeOperators,
             TypeFamilies ,
             ScopedTypeVariables
             #-}

{- Joel Svensson 2012, 2013
   Niklas Ulvinge 2013

  Notes:

  2013-01-24: Changes with the new Array types in mind
  2013-01-08: Edited
  2012-12-10: Edited

-} 


module Obsidian.CodeGen.InOut where 

import Obsidian.Exp 
import Obsidian.Array

import Obsidian.Types
import Obsidian.Globs 
import Obsidian.Program
import Obsidian.Force
import Obsidian.Memory

import qualified Obsidian.CodeGen.Program as CG 

import Data.Word
import Data.Int
      
---------------------------------------------------------------------------
-- New approach (hopefully)
---------------------------------------------------------------------------
-- "reify" Haskell functions into CG.Programs

{-
   Blocks needs to be of specific sizes (a design choice we've made).
   Because of this a prototypical input array needs to be provided
   that has a static block size (the number of blocks is dynamic).

   To make things somewhat general a heterogeneous list of input arrays
   that has same shape as the actual parameter list of the function
   is passed into toProgram (the reifyer). 

-} 
  
type Inputs = [(Name,Type)]


--class ToProgramB a where
--  toProgramB :: a -> (Inputs, CG.IM)


--class ToProgram a b where
--  toProgram :: Int -> (a -> b) -> Ips a b -> (Inputs,CG.IM)

class ToProgram a where
  toProgram :: Int -> a -> Ips' a -> (Inputs,CG.IM)


typeOf_ a = typeOf (Literal a)

---------------------------------------------------------------------------
-- Experimenting
---------------------------------------------------------------------------
--instance ToProgramB (GProgram a) where
--  toProgramB prg = ([],CG.compileStep1 prg)

--instance GlobalMemoryOps a => ToProgramB (Push Grid EWord32 a) where
--  toProgramB parr = toProgramB (forceG parr)

--instance GlobalMemoryOps a => ToProgramB (Push Grid Word32 a) where
--  toProgramB parr = toProgramB (forceG parr)



---------------------------------------------------------------------------
-- Base cases
--------------------------------------------------------------------------- 
instance ToProgram (GProgram a) where
  toProgram i prg a = ([],CG.compileStep1 prg)

instance GlobalMemoryOps a => ToProgram (Push Grid EWord32 a) where
  toProgram i parr a = toProgram i (forceG parr) a


instance (ToProgram b, Scalar t) => ToProgram (Pull EWord32 (Exp t) -> b) where
  toProgram i f (a :-> rest) = ((nom,Pointer t):ins,prg)
    where
      (ins,prg) = toProgram (i+1) (f input) rest
      nom  = "input" ++ show i
      n    = "n" ++ show i
      lengthVar = variable n
      input = namedGlobal nom lengthVar
      t     = typeOf_ (undefined :: t)
  
    --where nom = "s" ++ show i
    --      input = variable nom
     --     t = typeOf_ (undefined :: t)
{-
instance (Scalar t) => ToProgram (Pull (Exp Word32) (Exp t))(GProgram a) where
  toProgram i f (Pull n ixf) = ([(nom,Pointer t),(n,Word32)],CG.compileStep1 (f input)) 
      where nom = "input" ++ show i
            n   = "n" ++ show i 
            lengthVar = variable n
            input = namedGlobal nom lengthVar
            t = typeOf_ (undefined :: t)

instance (Scalar t) => ToProgram (Pull Word32 (Exp t)) (GProgram a) where
  toProgram i f (Pull n ixf) = ([(nom,Pointer t){-,(n,Word32)-}],CG.compileStep1 (f input)) 
      where nom = "input" ++ show i
            --n   = "n" ++ show i 
            --lengthVar = variable n
            input = namedGlobal nom n -- lengthVar
            t = typeOf_ (undefined :: t)
-} 
{- 
instance (Scalar t) => ToProgram (Exp t) (GProgram a) where
  toProgram i f a = ([(nom,t)],CG.compileStep1 (f input))
    where nom = "s" ++ show i
          input = variable nom
          t = typeOf_ (undefined :: t)

instance (Scalar t) => ToProgram (Pull (Exp Word32) (Exp t)) (GProgram a) where
  toProgram i f (Pull n ixf) = ([(nom,Pointer t),(n,Word32)],CG.compileStep1 (f input)) 
      where nom = "input" ++ show i
            n   = "n" ++ show i 
            lengthVar = variable n
            input = namedGlobal nom lengthVar
            t = typeOf_ (undefined :: t)

instance (Scalar t) => ToProgram (Pull Word32 (Exp t)) (GProgram a) where
  toProgram i f (Pull n ixf) = ([(nom,Pointer t){-,(n,Word32)-}],CG.compileStep1 (f input)) 
      where nom = "input" ++ show i
            --n   = "n" ++ show i 
            --lengthVar = variable n
            input = namedGlobal nom n -- lengthVar
            t = typeOf_ (undefined :: t)


---------------------------------------------------------------------------
-- More natural to work with these in some cases
---------------------------------------------------------------------------
instance (ToProgram b (GProgram ()),
          GlobalMemoryOps a)
          => ToProgram b (Push Grid Word32 a) where
  toProgram i f arr = toProgram i (forceG . f)  arr

instance (ToProgram b (GProgram ()),
          GlobalMemoryOps a)
          => ToProgram b (Push Grid EWord32 a) where
  toProgram i f arr = toProgram i (forceG . f)  arr


---------------------------------------------------------------------------
-- Recursive cases
--------------------------------------------------------------------------- 
instance (Scalar t, ToProgram b c) => ToProgram (Exp t) (b -> c) where
  toProgram i f (a :-> rest) = ((nom,t):ins,prg)
    where
      (ins,prg) = toProgram (i+1) (f input) rest
      nom = "s" ++ show i
      input = variable nom
      t = typeOf_ (undefined :: t)

instance (Scalar t, ToProgram b c) => ToProgram (Pull (Exp Word32) (Exp t)) (b -> c) where
  toProgram i f ((Pull n ixf) :-> rest) = ((nom,Pointer t):(n,Word32):ins,prg)
    where
      (ins,prg) = toProgram (i+1) (f input) rest
      nom = "input" ++ show i
      n   = "n" ++ show i
      lengthVar = variable n
      input = namedGlobal nom lengthVar
      t = typeOf_ (undefined :: t)


instance (Scalar t, ToProgram b c) => ToProgram (Pull Word32 (Exp t)) (b -> c) where
  toProgram i f ((Pull n ixf) :-> rest) = ((nom,Pointer t){-:(n,Word32)-}:ins,prg)
    where
      (ins,prg) = toProgram (i+1) (f input) rest
      nom = "input" ++ show i
      --n   = "n" ++ show i
      --lengthVar = variable n
      input = namedGlobal nom n --lengthVar
      t = typeOf_ (undefined :: t)

-}
---------------------------------------------------------------------------
-- heterogeneous lists of inputs 
---------------------------------------------------------------------------
data head :-> tail = head :-> tail

infixr 5 :->


---------------------------------------------------------------------------
-- Function types to input list types. 
---------------------------------------------------------------------------

type family Ips' a

type instance Ips' (a -> b)        = a :-> (Ips' b)
type instance Ips' (Push Grid l b) = ()
type instance Ips' (GProgram b)    = () 

--type family Ips a b
 
--type instance Ips a (Push Grid l b) = a
--type instance Ips a (Pull l b) = a
--type instance Ips a (GProgram b) = a
--type instance Ips a (b -> c) =  a :-> Ips b c


