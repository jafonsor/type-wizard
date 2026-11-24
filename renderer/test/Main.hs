module Main (main) where

import Control.Monad (unless)
import Data.Word (Word8)
import Foreign.Marshal.Array (peekArray, withArray)
import Foreign.Ptr (Ptr, castPtr)
import Test.HUnit hiding (Node)

import Renderer.Internal

main :: IO ()
main = do
  result <- runTestTT (TestList [flattenTests, cameraTests, packTests])
  unless (errors result == 0 && failures result == 0) (ioError (userError "tests failed"))

-- Helpers ----------------------------------------------------------------

near :: String -> Float -> Float -> Assertion
near msg expected actual =
  assertBool (msg <> ": expected " <> show expected <> ", got " <> show actual)
    (abs (expected - actual) < 1e-4)

nearV :: String -> V2 -> V2 -> Assertion
nearV msg (V2 ex ey) (V2 ax ay) = near (msg <> " x") ex ax >> near (msg <> " y") ey ay

nearL :: String -> [Float] -> [Float] -> Assertion
nearL msg es as = do
  assertEqual (msg <> " length") (length es) (length as)
  mapM_ (\(i, e, a) -> near (msg <> " [" <> show i <> "]") e a) (zip3 [0 :: Int ..] es as)

at :: Float -> Float -> Transform
at x y = Transform (V2 x y) 0 (V2 1 1)

white, red :: Colour
white = Colour 1 1 1 1
red = Colour 1 0 0 1

scene :: [Node] -> [Node] -> Scene
scene = Scene (Camera (V2 0 0) 20)

-- | Where an instance puts the unit square's centre.
centreOf :: Instance -> V2
centreOf i = applyAffine i.affine (V2 0 0)

-- Flatten ----------------------------------------------------------------

flattenTests :: Test
flattenTests = TestLabel "flatten" $ TestList
  [ "a Square is one instance, at its position, with its size" ~: do
      let i = only (flatten 1.5 (scene [Square (Transform (V2 3 4) 0 (V2 2 2)) red] []))
      i.kind @?= KSquare
      i.space @?= World
      i.colour @?= red
      nearV "centre" (V2 3 4) (centreOf i)
      nearV "corner" (V2 4 5) (applyAffine i.affine (V2 0.5 0.5))
  , "a Triangle keeps its kind" ~: do
      let i = only (flatten 1 (scene [Triangle (at 0 0) white] []))
      i.kind @?= KTriangle
  , "nested transforms compose parent after child: scale, then rotate, then translate" ~: do
      -- Parent: at (10, 0), scaled by 2. Child: at (1, 0). The child centre is
      -- at 10 + 2 * 1 = 12.
      let parent = Transform (V2 10 0) 0 (V2 2 2)
          i = only (flatten 1 (scene [Group parent [Square (at 1 0) white]] []))
      nearV "centre" (V2 12 0) (centreOf i)
  , "a rotated parent rotates the child's offset" ~: do
      let parent = Transform (V2 0 0) (pi / 2) (V2 1 1)
          i = only (flatten 1 (scene [Group parent [Square (at 1 0) white]] []))
      nearV "centre" (V2 0 1) (centreOf i)
  , "a parent's non-uniform scale stretches the child" ~: do
      let parent = Transform (V2 0 0) 0 (V2 3 1)
          i = only (flatten 1 (scene [Group parent [Square (Transform (V2 1 1) 0 (V2 1 1)) white]] []))
      nearV "centre" (V2 3 1) (centreOf i)
      nearV "corner" (V2 4.5 1.5) (applyAffine i.affine (V2 0.5 0.5))
  , "three levels compose in order" ~: do
      let a = Transform (V2 1 0) 0 (V2 1 1)
          b = Transform (V2 0 1) (pi / 2) (V2 1 1)
          c = Transform (V2 2 0) 0 (V2 1 1)
          i = only (flatten 1 (scene [Group a [Group b [Square c white]]] []))
      -- c at (2,0); b rotates it to (0,2), moves by (0,1): (0,3); a: (1,3).
      nearV "centre" (V2 1 3) (centreOf i)
  , "a Plus Sign is a Group of two Squares: two instances sharing the group transform" ~: do
      let plus = Group (at 5 5) [Square (Transform (V2 0 0) 0 (V2 1 0.2)) white, Square (Transform (V2 0 0) 0 (V2 0.2 1)) white]
          is = flatten 1 (scene [plus] [])
      length is @?= 2
      mapM_ (nearV "centre" (V2 5 5) . centreOf) is
  , "tree order is draw order, siblings then children in place" ~: do
      let tree =
            [ Square (at 1 0) red
            , Group (at 0 0) [Square (at 2 0) red, Triangle (at 3 0) white]
            , Square (at 4 0) white
            ]
          xs = [x | i <- flatten 1 (scene tree []), let V2 x _ = centreOf i]
      xs @?= [1, 2, 3, 4]
  , "the world draws first, then the overlay, each in its own space" ~: do
      let is = flatten 1 (scene [Square (at 1 0) red] [Square (at 2 0) white, Square (at 3 0) red])
      map (.space) is @?= [World, Overlay, Overlay]
      map (\i -> let V2 x _ = centreOf i in x) is @?= [1, 2, 3]
  , "an empty scene has no instances" ~: flatten 1 (scene [] []) @?= []
  , "a DotGrid covers the view, anchored to the world, and one dot is its diameter wide" ~: do
      -- Height 20, aspect 2: view is x in [-20, 20], y in [-10, 10]. Spacing 2:
      -- 21 columns by 11 rows (dots on the edges count, as they overlap the view).
      let is = flatten 2 (scene [DotGrid 2 0.08 white] [])
      length is @?= 21 * 11
      assertBool "all dots" (all ((== KDot) . (.kind)) is)
      let d0 = only (take 1 is)
      nearV "first dot" (V2 (-20) (-10)) (centreOf d0)
      near "diameter" 0.16 (let Affine a _ _ _ _ _ = d0.affine in a)
  , "a DotGrid follows the Camera by whole spacings (it scrolls with pans)" ~: do
      let cam = Camera (V2 3 0) 20
          is = flatten 1 (Scene cam [DotGrid 2 0.08 white] [])
          xs = [x | i <- is, let V2 x _ = centreOf i]
      assertBool "min x is the first multiple of 2 at or past 3 - 10 - 0.08" (minimum xs == -6)
      assertBool "max x" (maximum xs == 12)
  , "a DotGrid with a spacing too small for the view draws nothing instead of hanging" ~:
      flatten 1 (scene [DotGrid 0.001 0.0005 white] []) @?= []
  , "a DotGrid of zero spacing or radius draws nothing" ~: do
      flatten 1 (scene [DotGrid 0 0.1 white] []) @?= []
      flatten 1 (scene [DotGrid 2 0 white] []) @?= []
  , "a DotGrid draws where it sits in the tree" ~: do
      let is = flatten 1 (Scene (Camera (V2 0 0) 4) [Square (at 0 0) red, DotGrid 2 0.1 white, Square (at 0 0) red] [])
      map (.kind) is @?= [KSquare] <> replicate 9 KDot <> [KSquare]
  , "an overlay DotGrid ignores the Camera centre" ~: do
      let is = flatten 1 (Scene (Camera (V2 100 100) 4) [] [DotGrid 2 0.1 white])
      map (.space) is @?= replicate 9 Overlay
      nearV "first" (V2 (-2) (-2)) (centreOf (only (take 1 is)))
  , "Text: one instance per character, left anchored from the position" ~: do
      let is = flatten 1 (scene [Text (at 10 5) AnchorLeft 2 [('a', red), ('b', white)]] [])
      length is @?= 2
      -- cell width 0.6 * 2 = 1.2; centres at 10 + 0.6 and 10 + 1.8
      nearV "a" (V2 10.6 5) (centreOf (is !! 0))
      nearV "b" (V2 11.8 5) (centreOf (is !! 1))
      map (.colour) is @?= [red, white]
      near "cell height" 2 (let Affine _ _ _ d _ _ = (is !! 0).affine in d)
      near "cell width" 1.2 (let Affine a _ _ _ _ _ = (is !! 0).affine in a)
  , "Text: centre and right anchors shift the line" ~: do
      let go anchor = [x | i <- flatten 1 (scene [Text (at 0 0) anchor 1 [('a', red), ('b', red)]] []), let V2 x _ = centreOf i]
      nearL "centre" [-0.3, 0.3] (go AnchorCentre)
      nearL "right" [-0.9, -0.3] (go AnchorRight)
      nearL "left" [0.3, 0.9] (go AnchorLeft)
  , "Text: a space advances but has no instance" ~: do
      let is = flatten 1 (scene [Text (at 0 0) AnchorLeft 1 [('a', red), (' ', red), ('b', red)]] [])
      length is @?= 2
      nearV "b is two cells in" (V2 1.5 0) (centreOf (is !! 1))
  , "Text: glyph indices follow printable ASCII, others draw as a question mark" ~: do
      glyphIndex '!' @?= Just 0
      glyphIndex 'A' @?= Just 32
      glyphIndex '~' @?= Just 93
      glyphIndex ' ' @?= Nothing
      glyphIndex '\n' @?= glyphIndex '?'
      glyphIndex '\233' @?= glyphIndex '?'
  , "Text: transforms of the node and its group apply to the line" ~: do
      let t = Text (Transform (V2 0 0) 0 (V2 2 2)) AnchorLeft 1 [('a', red)]
          i = only (flatten 1 (scene [Group (at 10 0) [t]] []))
      nearV "centre" (V2 10.6 0) (centreOf i)
      near "scaled width" 1.2 (let Affine a _ _ _ _ _ = i.affine in a)
  , "Text in the overlay is flagged as overlay" ~: do
      let is = flatten 1 (scene [] [Text (at 0 0) AnchorLeft 1 [('a', red)]])
      map (.space) is @?= [Overlay]
  ]

-- Camera -----------------------------------------------------------------

-- | Column-major 3x3 times a point.
apply3 :: [Float] -> V2 -> V2
apply3 [a, b, _, c, d, _, tx, ty, _] (V2 x y) = V2 (a * x + c * y + tx) (b * x + d * y + ty)
apply3 m _ = error ("not a 3x3: " <> show m)

cameraTests :: Test
cameraTests = TestLabel "camera" $ TestList
  [ "the Camera centre maps to the middle of the screen" ~:
      nearV "centre" (V2 0 0) (apply3 (cameraMatrix 1.5 (Camera (V2 7 (-3)) 20)) (V2 7 (-3)))
  , "the world height spans the clip height, whatever the aspect" ~: do
      let m = cameraMatrix 2 (Camera (V2 0 0) 20)
      nearV "top" (V2 0 1) (apply3 m (V2 0 10))
      nearV "bottom" (V2 0 (-1)) (apply3 m (V2 0 (-10)))
  , "the width follows the aspect ratio" ~: do
      let m = cameraMatrix 2 (Camera (V2 0 0) 20)
      nearV "right" (V2 1 0) (apply3 m (V2 20 0))
      nearV "left" (V2 (-1) 0) (apply3 m (V2 (-20) 0))
      let sq = cameraMatrix 1 (Camera (V2 0 0) 20)
      nearV "square view" (V2 1 0) (apply3 sq (V2 10 0))
  , "it is the orthographic matrix, column-major, in the exact layout the shader reads" ~:
      nearL "matrix" [0.05, 0, 0, 0, 0.1, 0, -0.5, 0.3, 1] (cameraMatrix 2 (Camera (V2 10 (-3)) 20))
  , "a pan moves the world the other way" ~:
      nearV "a point at the old centre" (V2 (-0.1) 0) (apply3 (cameraMatrix 1 (Camera (V2 1 0) 20)) (V2 0 0))
  , "the overlay ignores the Camera centre and keeps its height" ~: do
      let cam = Camera (V2 50 50) 20
      nearV "origin" (V2 0 0) (apply3 (overlayMatrix 2 cam) (V2 0 0))
      nearV "edge" (V2 1 1) (apply3 (overlayMatrix 2 cam) (V2 20 10))
  , "a degenerate height or aspect does not give NaN or infinity" ~:
      assertBool "finite" (all (\x -> not (isNaN x || isInfinite x)) (cameraMatrix 0 (Camera (V2 0 0) 0)))
  ]

-- Packing ----------------------------------------------------------------

packTests :: Test
packTests = TestLabel "pack" $ TestList
  [ "the layout constants agree with the field list" ~:
      length instanceFields @?= instanceFloats
  , "an empty scene is the header only: the world matrix, then the overlay matrix" ~: do
      let (n, fs) = packScene 2 (scene [] [])
      n @?= 0
      length fs @?= headerFloats
      nearL "world" (cameraMatrix 2 (Camera (V2 0 0) 20)) (take 9 fs)
      nearL "overlay" (overlayMatrix 2 (Camera (V2 0 0) 20)) (drop 9 fs)
  , "the instance count and total length follow the node count" ~: do
      let (n, fs) = packScene 1 (scene [Square (at 0 0) red, Triangle (at 1 1) white, Group (at 0 0) [Square (at 2 2) red]] [Square (at 0 0) white])
      n @?= 4
      length fs @?= headerFloats + 4 * instanceFloats
  , "one instance is kind, glyph, space, the affine, then the colour" ~: do
      let i = Instance KSquare World (Affine 1 2 3 4 5 6) (Colour 0.1 0.2 0.3 0.4)
      nearL "square" [0, 0, 0, 1, 2, 3, 4, 5, 6, 0.1, 0.2, 0.3, 0.4] (packInstance i)
      nearL "triangle overlay" [1, 0, 1] (take 3 (packInstance i {kind = KTriangle, space = Overlay}))
      nearL "dot" [2, 0, 0] (take 3 (packInstance i {kind = KDot}))
      nearL "glyph" [3, 41, 0] (take 3 (packInstance i {kind = KGlyph 41}))
  , "instances follow the header, in draw order" ~: do
      let (_, fs) = packScene 1 (scene [Square (at 1 0) red] [Triangle (at 2 0) white])
          rows = chunks instanceFloats (drop headerFloats fs)
      map (!! 0) rows @?= [0, 1]
      map (!! 2) rows @?= [0, 1]
      map (!! 7) rows @?= [1, 2]
      map (!! 9) rows @?= [1, 1]
  , "text becomes one glyph instance per printable character, with its colour" ~: do
      let (n, fs) = packScene 1 (scene [] [Text (at 0 0) AnchorLeft 1 [('H', red), ('i', white)]])
          rows = chunks instanceFloats (drop headerFloats fs)
      n @?= 2
      map (!! 0) rows @?= [3, 3]
      map (!! 1) rows @?= [fromIntegral (fromEnum 'H' - 33), fromIntegral (fromEnum 'i' - 33)]
      map (take 4 . drop 9) rows @?= [[1, 0, 0, 1], [1, 1, 1, 1]]
  , "the bytes are little-endian IEEE floats at the documented offsets" ~: do
      let (_, fs) = packScene 1 (scene [Square (at 0 0) (Colour 1 0.5 0.25 1)] [])
      bytes <- withArray fs \p -> peekArray (length fs * 4) (castPtr p :: Ptr Word8)
      -- Colour red 1.0 is 00 00 80 3f; green 0.5 is 00 00 00 3f.
      let colourAt = (headerFloats + 9) * 4
      take 4 (drop colourAt bytes) @?= [0x00, 0x00, 0x80, 0x3f]
      take 4 (drop (colourAt + 4) bytes) @?= [0x00, 0x00, 0x00, 0x3f]
      length bytes @?= (headerFloats + instanceFloats) * 4
  ]

only :: [a] -> a
only [x] = x
only _ = error "expected exactly one"

chunks :: Int -> [a] -> [[a]]
chunks _ [] = []
chunks n xs = let (a, b) = splitAt n xs in a : chunks n b
