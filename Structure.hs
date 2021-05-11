{-# LANGUAGE FlexibleInstances, DeriveFunctor, DeriveTraversable #-}

module Structure
( OrientedTree (..)
, Orientation (..)
, Choice (..)
, Slice (..)
, PrefixTree(..)
, toGroup
, getAllPaths
, getAllValues
, applySF
, flatten
, elevate
, depth
, smallestDefault
, atDepth
, applyTT
, depthRange
, widthRange
, widthsAtDepth
, keys
, elevatePT
) where

import Data.List
import Data.Maybe


-- ORIENTED TREE ---------------------------------------------------------------

data Orientation = H | V deriving (Show)  -- Horizontal | Vertical

data OrientedTree a = Val a | Group Orientation [OrientedTree a]
 deriving (Foldable, Traversable)

instance Functor (OrientedTree) where
  fmap f (Val a) = Val (f a)
  fmap f (Group o trees) = Group o (map (fmap f) trees)

instance Applicative OrientedTree where
   pure = Val
   Val f <*> Val x = Val (f x)
   Val f <*> Group o xs = Group o (map (fmap f) xs)
   (Group o fs) <*> (Val x) = Group o (map (fmap ($ x)) fs)
   Group o fs <*> Group ox xs = Group o $ (map (<*> (Group ox xs)) fs)

instance Monad OrientedTree where
   return = Val
   Val a >>= f = f a
   Group o trees >>= f = Group o $ map (>>= f) trees

pad :: Int -> String
pad 0 = ""
pad n = " " ++ pad (n-1)

showTree :: (Show a) => Int -> OrientedTree a -> String
showTree n (Val x) = pad n ++ show x
showTree n (Group H treez) = pad n ++ "H\n" ++ horiShow
  where horiShow = concat $ map (\t -> showTree (n + 2)t ++ "\n") treez
showTree n (Group V treez) = "\n" ++ pad n ++ "V: " ++ vertShow ++ "\n"
  where vertShow = concat $ intersperse " " $ map (showTree 1) treez

instance (Show a) => Show (OrientedTree a) where
  show x = "\n" ++ showTree 0 x

toGroup :: Orientation -> [a] -> OrientedTree a
toGroup H prims = Group H (map (\x -> Val x) prims)
toGroup V prims = Group V (map (\x -> Val x) prims)

flatten :: OrientedTree a -> [a]
flatten (Val x) = [x]
flatten (Group _ vals) = concat $ map flatten vals

elevate :: [a] -> OrientedTree a -> OrientedTree a
elevate flat tree = fmap ff $ enumerate tree where
  ff (idx, value) = if idx < length flat then flat !! idx else value

--flattens tree, applies a sequential function, and elevates to original form
applySF :: ([a] -> [a]) -> OrientedTree a -> OrientedTree a
applySF sf tree = elevate (sf $ flatten tree) tree

-- enumerates each Val from left to right
enumerate :: OrientedTree a -> OrientedTree (Int, a)
enumerate = snd . enumerate' 0

-- maybe make this only enumerate what is in the slice?
enumerate' :: Int -> OrientedTree a -> (Int, OrientedTree (Int, a))
enumerate' num (Val x) = (1, Val (num, x))
enumerate' num (Group o (x:xs)) = (size numGroups, Group o numTrees) where
  numGroups = foldl ff [(enumerate' num x)] xs
  ff prevGroups x = prevGroups ++ [enumerate' (num + size prevGroups) x]
  size = sum . map fst
  numTrees = map snd numGroups


  -- SIZE FUNCTIONS ------------------------------------------------------------

depth :: OrientedTree a -> Int
depth (Val a) = 1
depth (Group o trees) = 1 + maximum (map depth trees)

width :: OrientedTree a -> Int
width (Val a) = 1
width (Group o trees) = length (trees)

-- range of depth levels in tree:
depthRange :: OrientedTree a -> [Int]
depthRange tree = [0 .. (depth tree) -2] -- -1 bc of Vals, and -1 bc of 0-index

-- range of width levels in tree at a given depth:
widthRange :: OrientedTree a -> Int -> [Int]
widthRange tree depth = [0 .. minimum $ widthsAtDepth tree depth]
-- ^ min due to slicing, (and since the width at a depth is mostly constant)

widthsAtDepth :: OrientedTree a -> Int -> [Int]
widthsAtDepth tree depth = map (width . getElement tree) (paths depth tree)


-- PATH FUNCTIONS --------------------------------------------------------------

type Path = [Int]

-- paths to all elements at depth d:
paths :: Int -> OrientedTree a -> [Path]
paths d tree =
  let aps = allPaths tree
  in nub $ map (take (d)) aps -- depth is idx of path.

allPaths :: OrientedTree a -> [Path]
allPaths (Val x) = [[]]
allPaths (Group o trees) =
  concat [map (c:) (allPaths t) | (c,t) <- zip [0 .. ] trees]

-- needs to be with MAYBE:
getElement :: OrientedTree a -> Path -> OrientedTree a
getElement (Val a) [x] = error "element does not exist"
getElement tree [] = tree
getElement (Group o elems) (x:xs) = getElement (elems !! x) xs


-- SLICES ----------------------------------------------------------------------

-- TODO: define slicing in terms of paths?

--at each hierarchical level: select either some Branches or All:
data Choice = Some [Int] | All deriving (Show, Eq)

type Slice = [Choice]

instance Show (Slice -> Slice) where
  show st =  "ST" --  show $ st $ smallestDefault [st] (disabled for now)
-- ^ in order to show slice transformation (a function), apply to default slice

-- ---- ---- SLICE CONSTRUCTION ------------------------------------------------

--crashes if lvl >= length slice (might fix with Maybe)
atLevel :: Int -> [Int] -> (Slice -> Slice)
atLevel lvl selection slice =
  let (first, second) = splitAt lvl (reverse slice)
  in reverse $ first ++ [Some selection] ++ tail second

-- selection should be a Choice, like in atDepth, problem occurs with getDepth...
-- ideally this should return a maybe but it is a lot of work just for idealism:
atDepth :: Int -> [Int] -> (Slice -> Slice) -- is used by partial application
atDepth lvl selection slice =
  let (first, second) = splitAt lvl slice
  in first ++ [Some selection] ++ tail second

atDepth' :: Int -> Choice -> (Slice -> Slice) -- is used by partial application
atDepth' lvl choice slice =
  let (first, second) = splitAt lvl slice
  in first ++ [choice] ++ tail second

smallestDefault :: [Slice -> Slice] -> Slice
smallestDefault sts = replicate ((getMaxDepth sts) + 1) All

getMaxDepth :: [Slice -> Slice] -> Int
getMaxDepth sts = maximum $ map getDepth sts

-- a piece cannot have more that 666 hierarchical levels, should be generalized
getDepth :: (Slice -> Slice) -> Int
getDepth sTrans = maximum $ findIndices (isSome) $ sTrans $ replicate (666) All

isSome (Some xs) = True
isSome _  = False

-- ---- ---- ACCESS ORIENTED TREE BY SLICE -------------------------------------

getElements :: Slice -> OrientedTree a -> [OrientedTree a]
getElements [All] (Group _ ts) = ts
getElements [Some idxs] (Group _ ts) = map (ts !!) idxs
getElements (All : slice) (Group _ ts) = concat $ map (getElements slice) ts
getElements (Some idxs : slice) (Group _ ts) =
   concat $ map (getElements slice) (map (ts !!) idxs)

type TreeTransformation a = (OrientedTree a -> OrientedTree a)

-- | slices should not be able to be longer than depth of tree - 1:
applyTT :: Slice -> TreeTransformation a -> OrientedTree a -> Maybe (OrientedTree a)
applyTT _ tt (Val x) = Nothing -- Cannot make a choice in a Val (only Groups)
applyTT slice tt tree@(Group o ts) =
  if length slice > (depth tree) - 1
    then Nothing
    else Just $ applyTT' slice tt tree

applyTT' :: Slice -> TreeTransformation a -> OrientedTree a -> OrientedTree a
applyTT' _ tt (Val x) = tt $ Val x
-- | (can't happen) ^ If Tree is a Val, slicing makes no sense: simply apply tt
applyTT' [c] tt (Group o ts) = Group o $ (handleChoice c) tt ts
-- |     ^ if slice is single choice, apply tt to chosen trees
applyTT' (c:cs) tt (Group o ts) = Group o $ (handleChoice c) (applyTT' cs tt) ts
-- |     ^ if more choices in slice, recursively continue down tree

handleChoice :: Choice -> ( (a -> a) -> [a] -> [a] )
handleChoice c = case c of
                  All -> map
                  Some idxs -> zipSome idxs

zipSome idxs f trees =
   zipWith (\tree idx -> if idx `elem` idxs then f tree else tree) trees [0..]

replaceVal :: a -> a -> a
replaceVal new old = new

-- PRE-FIX TREE ----------------------------------------------------------------

data PrefixTree v k = Leaf k v | Node k [PrefixTree v k] deriving (Show)

instance Functor (PrefixTree v) where
  fmap f (Leaf k v) = Leaf (f k) v
  fmap f (Node k trees) = Node (f k) (map (fmap f) trees)


lookupPT :: (Eq k) => PrefixTree v k -> [k] ->  Maybe v
lookupPT  _ [] = Nothing
lookupPT (Leaf k v) [x] = if x == k then Just v else Nothing
lookupPT (Leaf k v) (x:xs) = Nothing
lookupPT (Node k ptrees) (x:xs) =  if k == x then check else Nothing
  where check = case (find (\pt -> isJust $ lookupPT pt xs) ptrees) of
                  Just tree -> lookupPT tree xs
                  Nothing -> Nothing

getAllPaths :: PrefixTree v k -> [[k]]
getAllPaths (Leaf k v) = [[k]]
getAllPaths (Node k trees) =
  concat [map (k:) (getAllPaths t) | (t) <- trees]

getAllValues :: (Eq k) => PrefixTree v k -> [v]
getAllValues tree =
  let keys = getAllPaths tree
  in  map fromJust $ map (lookupPT tree) keys
  --  ^ should never be Nothing, since it only looks up paths from getallPaths

depthPT :: PrefixTree v k -> Int
depthPT (Leaf k v) = 1
depthPT (Node k trees) = 1 + maximum (map depthPT trees)

keys :: (PrefixTree k v) -> Int
keys (Leaf k v) = 1
keys (Node k trees) = 1 + (sum $ map keys trees)


elevatePT :: [k] -> PrefixTree v k -> PrefixTree v k
elevatePT flat tree = fmap ff $ enumeratePT tree where
  ff (idx, value) = if idx < length flat then flat !! idx else value

-- enumerates each Val from left to right
enumeratePT :: PrefixTree v k -> PrefixTree v (Int, k)
enumeratePT = snd . enumeratePT' 0

-- maybe make this only enumerate what is in the slice?
enumeratePT' :: Int -> PrefixTree v k -> (Int, PrefixTree v (Int, k))
enumeratePT' num (Leaf k v) = (1, Leaf (num, k) v)
enumeratePT' num (Node k (x:xs)) = (size numNodes + 1, Node (num, k) numTrees) where
  nextNum = num + 1
  numNodes = foldl ff [(enumeratePT' nextNum x)] xs
  ff prevGroups x = prevGroups ++ [enumeratePT' (nextNum + size prevGroups) x]
  size = sum . map fst
  numTrees = map snd numNodes


{-
  enumerate' :: Int -> OrientedTree a -> (Int, OrientedTree (Int, a))
  enumerate' num (Val x) = (1, Val (num, x))
  enumerate' num (Group o (x:xs)) = (size numGroups, Group o numTrees) where
    numGroups = foldl ff [(enumerate' num x)] xs
    ff prevGroups x = prevGroups ++ [enumerate' (num + size prevGroups) x]
    size = sum . map fst
    numTrees = map snd numGroups
-}
-- TESTING ---------------------------------------------------------------------

testMT :: OrientedTree Char
testMT =     Group H [
                Group V [
                  Val 'C',
                  Val 'A',
                  Val 'T'
                ],
                Group V [
                  Val 'D',
                  Val 'O',
                  Val 'G'
                ],
                Group H [
                  Group H [
                    Val 'K',
                    Val 'I',
                    Val 'L'
                  ],
                  Group H [
                    Val 'L',
                    Val 'E',
                    Val 'R'
                  ]
                ]
              ]

testOT :: OrientedTree Int
testOT = Group H [Group V [Val 1, Val 2, Val 3], Group V [Val 4, Val 5]]


testPT :: PrefixTree Int Char
testPT = Node 'C' [
          Node 'A' [
            Leaf 'T' 1,
            Leaf 'R' 2
          ],
          Node 'O' [
            Leaf 'P' 3,
            Node 'O' [
              Leaf 'L' 4
            ]
          ]
         ]


-- TODO allow the operation on sequences of notes that are not in the same group
-- TODO address merging trees
