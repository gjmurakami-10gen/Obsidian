{- Joel Svensson 2012
   Mary Sheeran  2012

   Notes:
   2012-12-10: Refactoring
               (adherence to new Array types and program types)  
-}

{-# LANGUAGE FlexibleInstances #-}

module Obsidian.Library where 

import Obsidian.Array 
import Obsidian.Exp 
import Obsidian.Program

import Data.Bits 
import Data.Word

import Prelude hiding (splitAt,zipWith,replicate)


-- TODO: Array Pull/Push a
--       do I have any Library functions that are Push/Pull agnostic? 
--       (There is concP that concatenates any 2 Pushable arrays) 

---------------------------------------------------------------------------
-- Functor instance Pull/Push arrays
---------------------------------------------------------------------------
instance Functor Pull where 
  fmap f arr = Pull (len arr) $ \ix -> f (arr ! ix) 

instance Functor Push where
  fmap f (Push n pfun) =
    Push n $ \wf -> pfun (\a ix -> wf (f a) ix)

instance Functor Distrib where
  fmap f (Distrib n bixf) = Distrib n $ \bix -> f (bixf bix)

instance Functor GlobArray where
  fmap f (GlobArray nb bs wf ) =
    GlobArray nb bs
    $ \wf' -> wf (\a bix tix -> wf' (f a) bix tix)

instance Functor Seq where
  fmap f (Seq n ixf) = Seq n $ \ix -> f (ixf ix) 

---------------------------------------------------------------------------
-- Reverse an array by indexing in it backwards
---------------------------------------------------------------------------
  
rev :: Pull a -> Pull a 
rev arr = mkPullArray n (\ix -> arr ! (m - ix))  
   where m = fromIntegral (n-1)
         n = len arr


---------------------------------------------------------------------------
-- split into sequential (fixed static) chunks 
---------------------------------------------------------------------------
sequentially :: Word32 -> Pull a -> (Pull (Seq a))
sequentially s arr =
  case n `mod` s of
    0 -> Pull chunks
         $ \ix -> Seq (fromIntegral s)
                      (\six -> arr ! (ix * (fromIntegral s) + six))
    _ -> error "sequentially: not evenly divisible" 
  where
    n = len arr
    chunks = n `div` s

-- If Seq are of dynamic length this operation is impossible.
-- To get around this a Seqsize is passed into the function.
unSequentially :: Word32 -> Pull (Seq a) -> Pull a
unSequentially ss arr =
  Pull n $ \i -> let six = i `mod` (fromIntegral ss)
                     ix  = i `div` (fromIntegral ss)
                 in (arr ! ix) ! six 
  where
    n = ss * len arr

---------------------------------------------------------------------------
-- split into sequential and potentially unbalanced chunks
---------------------------------------------------------------------------
seqUnbalanced :: Word32 -> (Exp Word32) -> Pull a -> (Pull (Seq a))
seqUnbalanced nChunks chunkSize arr = undefined 

         
---------------------------------------------------------------------------
-- splitAt (name clashes with Prelude.splitAt)
---------------------------------------------------------------------------
splitAt :: Integral i => i -> Pull a -> (Pull a, Pull a) 
splitAt n arr = (mkPullArray m (\ix -> arr ! ix), 
                 mkPullArray  (len arr - m) (\ix -> arr ! (ix + pos)))
  where pos = fromIntegral n
        m   = fromIntegral n


halve arr = splitAt n2 arr
  where 
    n = len arr
    n2 = n `div` 2

---------------------------------------------------------------------------
-- replicate 
---------------------------------------------------------------------------
replicate n a = mkPullArray n (\ix -> a)



---------------------------------------------------------------------------
-- Shift arrays
---------------------------------------------------------------------------
shiftRight :: Choice a => Word32 -> a -> Pull a -> Pull a
shiftRight dist elt arr = resize (len arr)
                          $ replicate dist elt `conc` arr

shiftLeft :: Choice a => Word32 -> a -> Pull a -> Pull a
shiftLeft dist elt arr = resize (len arr)
                         $ arr `conc`  replicate dist elt
                         
---------------------------------------------------------------------------
-- elements at even indices to fst output, odd to snd.
---------------------------------------------------------------------------
evenOdds :: Pull a -> (Pull a, Pull a)
evenOdds arr = (mkPullArray (n-n2) (\ix -> arr ! (2*ix)) ,
                mkPullArray n2     (\ix -> arr ! (2*ix + 1)))
  where
    n = fromIntegral (len arr)
    n2 = div n 2

---------------------------------------------------------------------------
-- Concatenate the arrays
---------------------------------------------------------------------------
conc :: Choice a => Pull a -> Pull a -> Pull a 
conc a1 a2 = mkPullArray (n1+n2)
               $ \ix -> ifThenElse (ix <* (fromIntegral n1)) 
                       (a1 ! ix) 
                       (a2 ! (ix - (fromIntegral n1)))
  where 
    n1 = len a1
    n2 = len a2 

    
---------------------------------------------------------------------------
-- zipp unzipp
---------------------------------------------------------------------------
unzipp :: Pull (a,b) -> (Pull a, Pull b)       
unzipp arr = (mkPullArray (len arr) (\ix -> fst (arr ! ix)) ,
              mkPullArray (len arr) (\ix -> snd (arr ! ix)) )
              
zipp :: (Pull a, Pull b) -> Pull (a, b)             
zipp (arr1,arr2) =  Pull (min (len arr1) (len arr2))
                      $ \ix -> (arr1 ! ix, arr2 ! ix) 

unzipp3 :: Pull (a,b,c) 
           -> (Pull a, Pull b, Pull c)       
unzipp3 arr = (fmap (\(x,_,_) -> x) arr,
               fmap (\(_,y,_) -> y) arr,
               fmap (\(_,_,z) -> z)  arr) 


zipp3 :: (Pull a, Pull b, Pull c) 
         -> Pull (a,b,c)             
zipp3 (arr1,arr2,arr3) = 
  mkPullArray (minimum [len arr1, len arr2, len arr3])
  (\ix -> (arr1 ! ix, arr2 ! ix, arr3 ! ix))
    


zipWith :: (a -> b -> c) -> Pull a -> Pull b -> Pull c
zipWith op a1 a2 =  
  mkPullArray (min (len a1) (len a2))
  (\ix -> (a1 ! ix) `op` (a2 ! ix))
                   
    
                   
---------------------------------------------------------------------------
-- pair 
---------------------------------------------------------------------------
pair :: Pull a -> Pull (a,a)
pair (Pull n ixf) = 
  mkPullArray n' (\ix -> (ixf (ix*2),ixf (ix*2+1))) 
  where 
    n' = n `div` 2 



unpair :: Choice a => Pull (a,a) -> Pull a
unpair arr = 
    let n = len arr
    in  mkPullArray (2*n) (\ix -> ifThenElse ((mod ix 2) ==* 0) 
                                  (fst (arr ! (ix `shiftR` 1)))
                                  (snd (arr ! (ix `shiftR` 1)))) 


---------------------------------------------------------------------------
-- twoK (untested for proper functionality) 
---------------------------------------------------------------------------
twoK ::Int -> (Pull a -> Pull b) -> Pull a -> Pull b 
twoK 0 f = f  -- divide 0 times and apply f
twoK n f =  (\arr -> 
              let arr' = mkPullArray lt (\i -> (f (mkPullArray  m (\j -> (arr ! (g i j)))) ! (h i))) 
                  m    = (len arr `shiftR` n)   --pow of two           
                  g i j = i .&. (fromIntegral (complement (m-1))) .|. j  
                  h i   = i .&. (fromIntegral (nl2-1))   -- optimize 

                  nl2   = (len (f (mkPullArray  m (\j -> arr ! variable "X"))))
                  lt    = nl2 `shiftL` n 
              in arr')
 

----------------------------------------------------------------------------
-- ***                          PUSHY LIBRARY                        *** ---
----------------------------------------------------------------------------

---------------------------------------------------------------------------
-- IxMap Class
---------------------------------------------------------------------------
class IxMap a where 
  ixMap :: (Exp Word32 -> Exp Word32) 
           -> a e 
           -> a e

instance IxMap Push where
  ixMap f (Push n p) = Push n (ixMap' f p)


instance IxMap Pull where 
  ixMap f (Pull n ixf) =  Pull n (ixf . f) 


-- like fmap but the function is applied to indices.. 
ixMap' :: (Exp Word32 -> Exp Word32) 
          -> ((a -> Exp Word32 -> TProgram ()) -> BProgram ()) 
          -> ((a -> Exp Word32 -> TProgram ()) -> BProgram ()) 
ixMap' f p = \wf -> p (\a ix -> wf a (f ix))


---------------------------------------------------------------------------
-- Concatenate on Push arrays 
---------------------------------------------------------------------------
concP :: (Pushable arr1,
          Pushable arr2) => (arr1 a, arr2 a) -> Push a     
concP (arr1,arr2) = 
  mkPushArray  (n1+n2)
  $ \wf ->
  do
    parr1 wf
    parr2 $ \a i -> wf a (fromIntegral n1 + i)
  
  where 
    (Push n1 parr1) = push arr1
    (Push n2 parr2) = push arr2


----------------------------------------------------------------------------
--
unpairP :: Pushable arr => arr (a,a) -> Push a
unpairP arr =
  Push n $ \k -> pushf (everyOther k)
  where
    parr@(Push n pushf) = push arr

everyOther :: (a -> Exp Word32 -> TProgram ()) 
              -> (a,a) -> Exp Word32 -> TProgram ()
everyOther wf (a,b) ix = wf a (ix * 2) >> wf b (ix * 2 + 1)  

---------------------------------------------------------------------------
-- zipP
---------------------------------------------------------------------------
zipP :: Pushable arr  => arr a -> arr a -> Push a  
zipP arr1 arr2 =
  Push (n1+n2)
  $ \func -> p1 (\a ix -> func a (2*ix)) >>
             p2 (\a ix -> func a (2*ix + 1))
         
  where 
    (Push n1 p1) = push arr1
    (Push n2 p2) = push arr2


