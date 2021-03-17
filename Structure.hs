module Structure
( OrientedTree (..)
, Orientation (..)
, treeToMusic
, addToGroup
, removeFromGroup
, replaceElement
) where

import Euterpea
import Data.List
import Control.Applicative

-- MUSICTREE -------------------------------------------------------------------

{-
 the grouping structure of a piece, represented as a
 polymorphic tree, with Euterpeas primitives (note or rest) as leaves.
 Each branch is labeled with an orientation H or V corr. to chord or line

 Similar structures already exists in euterpea, but re-implemented to allow
 things like grouping by slicing.
-}

data Orientation = H | V deriving (Show)  -- Horizontal | Vertical

data OrientedTree a = Val a | Group Orientation [OrientedTree a]

type MusicTree = OrientedTree (Primitive Pitch)

pad :: Int -> String
pad 0 = ""
pad n = " " ++ pad (n-1)

showTree :: (Show a) => Int -> OrientedTree a -> String
showTree n (Val x) = pad n ++ show x
showTree n (Group H treez) = "\n" ++ pad n ++ "H\n" ++ horiShow ++ "\n"
  where horiShow = concat $ map (showTree (n + 2)) treez
showTree n (Group V treez) = "\n" ++ pad n ++ "V: " ++ vertShow ++ "\n"
  where vertShow = concat $ intersperse "," $ map (showTree 1) treez

instance (Show a) => Show (OrientedTree a) where
  show x = showTree 0 x

-- converts from a piece of music from orientedTree to Euterpeas 'Music Pitch'
-- enables us to play the piece as MIDI with built-in Euterpea functions
treeToMusic :: MusicTree -> Music Pitch
treeToMusic (Val x) = valToMusic (Val x)
treeToMusic (Group H (x:xs)) = foldl series (treeToMusic x) xs
  where series acc x = acc :+: treeToMusic x
treeToMusic (Group V (x:xs)) = foldl parallel (treeToMusic x) xs
  where parallel acc x = acc :=: treeToMusic x

valToMusic :: MusicTree -> Music Pitch
valToMusic (Val x) = Prim (x)

-- PATH ------------------------------------------------------------------------

type Path = [Int]

getElement :: OrientedTree a -> Path -> OrientedTree a
getElement (Val a) [x] = error "element does not exist"
getElement tree [] = tree
getElement (Group o elems) (x:xs) = getElement (elems !! x) xs

-- if theres already an element x on path, e is inserted before x
addToGroup :: OrientedTree a -> OrientedTree a -> Path -> OrientedTree a
addToGroup tree element [] = tree
addToGroup (Group o elems) element [idx] = Group o (a ++ [element] ++ b)
  where (a, b) = splitAt idx elems
addToGroup (Group o elems) element (x:xs) = Group o newElems
  where (a,e:b) = splitAt x elems
        newElems = a ++ [addToGroup e element xs] ++ b

removeFromGroup :: OrientedTree a -> Path -> OrientedTree a
removeFromGroup tree [] = tree
removeFromGroup (Group o elems) [x] = Group o (a ++ b)
  where (a, e:b) = splitAt x elems
removeFromGroup (Group o elems) (x:xs) = Group o newElems
  where (a, e:b) = splitAt x elems
        newElems = a ++ [removeFromGroup e xs] ++ b

replaceElement :: OrientedTree a -> Path -> OrientedTree a -> OrientedTree a
replaceElement tree path newElement = newTree
  where newTree = addToGroup (removeFromGroup tree path) newElement path


-- SLICING ---------------------------------------------------------------------

data Choice = Some [Int] | All deriving Show

type Slice = [Choice]
--at each hierarchical level: select either some Branches or ALl

extract :: Slice -> OrientedTree a -> OrientedTree a
extract _ (Val x) = Val x
extract ([]) tree = tree
extract (All : slice) (Group o trees) =
   Group o $ map (extract slice) trees
extract (Some  idxs : slice) (Group o trees) =
   Group o $ map (extract slice) (map (trees !!) idxs)


--applies function to every element in slice
applyFunction :: (a -> a) -> Slice -> OrientedTree a -> OrientedTree a
applyFunction f _ (Val x) = Val (f x)
applyFunction f (All : slice) (Group o trees) =
  Group o $ map (applyFunction f slice) trees
applyFunction f (Some idxs : slice) (Group o trees) =
  Group o $ zipWith zf trees [0..] where
    zf tree idx = if idx `elem` idxs then applyFunction f slice tree else tree

replace :: a -> a -> a
replace new old = new

-- slice construction: allows the composition of (Slice -> Slice)
-- examples that apply to "testTree": (need to be generalized)
-- should they add? i.e. atVoices[0,1] . atVoices[2] = atVoices [0,1,2]?
-- right now atVoices[0,1] . atVoices[2] = atVoices [0,1]
atChords, atVoices :: [Int] -> Slice -> Slice
atChords selection [_ , choice] = [Some selection, choice]
atVoices selection [choice, _] = [choice, Some selection]

-- PRE-FIX TREE ----------------------------------------------------------------

data PrefixTree k v = Leaf k v | Node k [PrefixTree k v] deriving (Show)

type MusicPT =
   PrefixTree (Slice -> Slice) ((Primitive Pitch) -> (Primitive Pitch))

lookupPT :: (Eq k, Eq v) => [k] -> PrefixTree k v -> Maybe v
lookupPT [] _ = Nothing
lookupPT [x] (Leaf k v)  = if x == k then Just v else Nothing
lookupPT (x:xs) (Leaf k v) = Nothing
lookupPT (x:xs) (Node k ptrees) =  if k == x then check else Nothing
  where check = case (find (\pt -> lookupPT xs pt /= Nothing) ptrees) of
                  Just tree -> lookupPT xs tree
                  Nothing -> Nothing

-- TESTING ---------------------------------------------------------------------

testPT :: PrefixTree Char Int
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


testTree :: OrientedTree (Primitive Pitch)
testTree =
              Group H [
                Group V [
                  Val (Note hn (C,4)),
                  Val (Note hn (E,4)),
                  Val (Note hn (G,4))
                  ],
                Group V [
                  Val (Note hn (C,4)),
                  Val (Note hn (E,4)),
                  Val (Note hn (G,4))
                  ],
                Group V [
                  Val (Note hn (D,4)),
                  Val (Note hn (G,4)),
                  Val (Note hn (B,4))
                  ],
                Group V [
                  Val (Note hn (D,4)),
                  Val (Note hn (G,4)),
                  Val (Note hn (B,4))
                  ]
                ]

-- TODO Make the tree operations return maybe so we can allow failure..
-- TODO create slicing abilities like the prefix boyz have done
