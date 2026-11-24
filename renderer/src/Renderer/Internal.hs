{-# OPTIONS_GHC -Wno-partial-fields #-}

-- | The pure layer of the renderer: the scene types, the flatten from a node
-- tree to instances, the camera matrix and the packed buffer. It is exposed
-- for the tests (spec section 13) and for the "Renderer" module; the game
-- code imports "Renderer" only.
--
-- /Units./ The world is measured in world units; the Camera shows a fixed
-- 'cameraWorldHeight' of them from top to bottom and a width that follows the
-- aspect ratio. +x is right and +y is up. Rotation is counter-clockwise, in
-- radians. A 'Triangle' of rotation 0 points along +x.
--
-- /Text./ A glyph cell is 'glyphAspect' wide and 1 tall in units of the
-- text's height argument. The cell is centred on the text's position
-- vertically; 'Anchor' places the line horizontally.
--
-- /Buffer layout./ One frame is a flat sequence of 'Float's: a header of
-- 'headerFloats' (the world matrix, then the overlay matrix, each a column
-- major 3x3), then 'instanceFloats' per instance, in draw order. See
-- 'instanceFields'.
module Renderer.Internal
  ( -- * Public types (re-exported by "Renderer")
    V2 (..)
  , Transform (..)
  , Colour (..)
  , Anchor (..)
  , Node (..)
  , Camera (..)
  , Scene (..)
  , Viewport (..)
  , Frame (..)
    -- * Flatten
  , Affine (..)
  , identityAffine
  , fromTransform
  , composeAffine
  , applyAffine
  , Kind (..)
  , Space (..)
  , Instance (..)
  , flatten
  , glyphAspect
  , glyphIndex
  , maxDots
    -- * Camera
  , cameraMatrix
  , overlayMatrix
    -- * Packing
  , headerFloats
  , instanceFloats
  , instanceFields
  , packScene
  , packInstance
  ) where

import Data.Char (ord)

data V2 = V2 Float Float
  deriving stock (Eq, Show)

data Transform = Transform { position :: V2, rotation :: Float, scale :: V2 }
  deriving stock (Eq, Show)

-- | Straight RGBA, 0 to 1.
data Colour = Colour Float Float Float Float
  deriving stock (Eq, Show)

data Anchor = AnchorLeft | AnchorCentre | AnchorRight
  deriving stock (Eq, Show)

data Node
  = Group Transform [Node]
  | Square Transform Colour
  | Triangle Transform Colour
  | DotGrid { spacing :: Float, radius :: Float, colour :: Colour }
  | Text Transform Anchor Float [(Char, Colour)]
  deriving stock (Eq, Show)

data Camera = Camera { cameraCentre :: V2, cameraWorldHeight :: Float }
  deriving stock (Eq, Show)

data Scene = Scene { sceneCamera :: Camera, sceneWorld :: [Node], sceneOverlay :: [Node] }
  deriving stock (Eq, Show)

-- | The canvas size in CSS pixels, and width over height.
data Viewport = Viewport { width :: Float, height :: Float, aspect :: Float }
  deriving stock (Eq, Show)

-- | What the pull function gets each frame: the viewport and the rAF
-- timestamp in seconds.
data Frame = Frame { viewport :: Viewport, time :: Double }
  deriving stock (Eq, Show)

-- | A 2D affine map: @(x, y) -> (a x + c y + tx, b x + d y + ty)@.
data Affine = Affine !Float !Float !Float !Float !Float !Float
  deriving stock (Eq, Show)

identityAffine :: Affine
identityAffine = Affine 1 0 0 1 0 0

-- | Translate by the position after rotating and scaling: @T * R * S@.
fromTransform :: Transform -> Affine
fromTransform (Transform (V2 px py) r (V2 sx sy)) =
  Affine (c * sx) (s * sx) (negate s * sy) (c * sy) px py
  where
    c = cos r
    s = sin r

-- | @composeAffine parent child@ applies the child first, then the parent.
composeAffine :: Affine -> Affine -> Affine
composeAffine (Affine pa pb pc pd px py) (Affine qa qb qc qd qx qy) =
  Affine
    (pa * qa + pc * qb)
    (pb * qa + pd * qb)
    (pa * qc + pc * qd)
    (pb * qc + pd * qd)
    (pa * qx + pc * qy + px)
    (pb * qx + pd * qy + py)

applyAffine :: Affine -> V2 -> V2
applyAffine (Affine a b c d tx ty) (V2 x y) = V2 (a * x + c * y + tx) (b * x + d * y + ty)

-- | What one instance is. The shape is drawn in the unit square centred on
-- the origin: a 'Square' fills it, a 'Triangle' has its base on the left
-- edge and its apex at the middle of the right edge, a 'Dot' is the inscribed
-- circle, and a 'Glyph' is the atlas cell for the given index.
data Kind = KSquare | KTriangle | KDot | KGlyph Int
  deriving stock (Eq, Show)

-- | World instances use the Camera, overlay instances do not.
data Space = World | Overlay
  deriving stock (Eq, Show)

data Instance = Instance
  { kind :: Kind
  , space :: Space
  , affine :: Affine
  , colour :: Colour
  }
  deriving stock (Eq, Show)

-- | The width of a glyph cell over its height. The JS atlas draws into cells
-- of this shape.
glyphAspect :: Float
glyphAspect = 0.6

-- | The atlas index of a character: printable ASCII from @!@ (0) to @~@ (93).
-- A space has no instance. Anything else draws as @?@.
glyphIndex :: Char -> Maybe Int
glyphIndex ' ' = Nothing
glyphIndex ch
  | o > 32 && o < 127 = Just (o - 33)
  | otherwise = Just (ord '?' - 33)
  where
    o = ord ch

-- | A DotGrid that would need more dots than this draws none (a guard
-- against a spacing that is tiny next to the view).
maxDots :: Int
maxDots = 50_000

-- | The draw order: 'sceneWorld' in tree order, then 'sceneOverlay'. The
-- aspect ratio is needed for the extent of a 'DotGrid'.
--
-- A 'DotGrid' ignores the transforms of the groups around it: it is anchored
-- to the world (or, in the overlay, to the screen centre) and covers the
-- visible area.
flatten :: Float -> Scene -> [Instance]
flatten asp (Scene cam world overlay) =
  concatMap (node World centre0 identityAffine) world
    <> concatMap (node Overlay (V2 0 0) identityAffine) overlay
  where
    Camera centre0 worldHeight = cam
    halfH = worldHeight / 2
    halfW = halfH * asp

    node :: Space -> V2 -> Affine -> Node -> [Instance]
    node sp centre parent = \case
      Group t kids -> concatMap (node sp centre (composeAffine parent (fromTransform t))) kids
      Square t c -> [Instance KSquare sp (composeAffine parent (fromTransform t)) c]
      Triangle t c -> [Instance KTriangle sp (composeAffine parent (fromTransform t)) c]
      DotGrid s r c -> dots sp centre s r c
      Text t anchor h chars ->
        let base = composeAffine parent (fromTransform t)
            adv = glyphAspect * h
            total = adv * fromIntegral (length chars)
            start = case anchor of
              AnchorLeft -> 0
              AnchorCentre -> negate total / 2
              AnchorRight -> negate total
        in [ Instance (KGlyph g) sp (composeAffine base (Affine adv 0 0 h gx 0)) c
           | (i, (ch, c)) <- zip [0 :: Int ..] chars
           , Just g <- [glyphIndex ch]
           , let gx = start + (fromIntegral i + 0.5) * adv
           ]

    dots sp (V2 cx cy) s r c
      | s <= 0 || r <= 0 || nx <= 0 || ny <= 0 || nx * ny > maxDots = []
      | otherwise =
          [ Instance KDot sp (Affine d 0 0 d (fromIntegral i * s) (fromIntegral j * s)) c
          | j <- [j0 .. j1]
          , i <- [i0 .. i1]
          ]
      where
        d = 2 * r
        i0 = ceiling ((cx - halfW - r) / s) :: Int
        i1 = floor ((cx + halfW + r) / s) :: Int
        j0 = ceiling ((cy - halfH - r) / s) :: Int
        j1 = floor ((cy + halfH + r) / s) :: Int
        nx = i1 - i0 + 1
        ny = j1 - j0 + 1

-- | World to clip space, column-major 3x3: the Camera centre goes to the
-- middle of the screen, 'cameraWorldHeight' spans the height, and the width
-- follows the aspect ratio.
cameraMatrix :: Float -> Camera -> [Float]
cameraMatrix asp (Camera (V2 cx cy) worldHeight) =
  [ sx, 0, 0
  , 0, sy, 0
  , negate cx * sx, negate cy * sy, 1
  ]
  where
    h = max 1e-6 worldHeight
    sy = 2 / h
    sx = sy / max 1e-6 asp

-- | The same for the overlay: the origin is the middle of the screen, the
-- Camera's centre is ignored, its height is kept.
overlayMatrix :: Float -> Camera -> [Float]
overlayMatrix asp (Camera _ worldHeight) = cameraMatrix asp (Camera (V2 0 0) worldHeight)

-- | Floats before the first instance: two 3x3 matrices.
headerFloats :: Int
headerFloats = 18

-- | Floats per instance.
instanceFloats :: Int
instanceFloats = 13

-- | The instance layout, in order: kind (0 square, 1 triangle, 2 dot, 3
-- glyph), glyph index (0 unless a glyph), space (0 world, 1 overlay), the
-- affine @a b c d tx ty@, and the colour @r g b a@. @instanceFields@ names
-- them for the JS side to read the same layout.
instanceFields :: [String]
instanceFields = ["kind", "glyph", "space", "a", "b", "c", "d", "tx", "ty", "r", "g", "b", "a"]

packInstance :: Instance -> [Float]
packInstance (Instance k sp (Affine a b c d tx ty) (Colour r g bl al)) =
  [kindCode, glyph, spaceCode, a, b, c, d, tx, ty, r, g, bl, al]
  where
    (kindCode, glyph) = case k of
      KSquare -> (0, 0)
      KTriangle -> (1, 0)
      KDot -> (2, 0)
      KGlyph i -> (3, fromIntegral i)
    spaceCode = case sp of
      World -> 0
      Overlay -> 1

-- | The whole frame: the header, then every instance. The first component is
-- the instance count.
packScene :: Float -> Scene -> (Int, [Float])
packScene asp scene = (length insts, header <> concatMap packInstance insts)
  where
    insts = flatten asp scene
    header = cameraMatrix asp (sceneCamera scene) <> overlayMatrix asp (sceneCamera scene)
