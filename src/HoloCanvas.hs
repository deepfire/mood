{-# OPTIONS_GHC -fplugin GHC.TypeLits.Normalise #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.Extra.Solver #-}
{-# LANGUAGE GADTs, TypeFamilies, TypeFamilyDependencies, TypeInType #-}
{-# LANGUAGE GeneralizedNewtypeDeriving, StandaloneDeriving #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE ExplicitForAll, FlexibleContexts, FlexibleInstances, MultiParamTypeClasses, RankNTypes, UndecidableInstances #-}
{-# LANGUAGE LambdaCase, OverloadedStrings, PartialTypeSignatures, RecordWildCards, ScopedTypeVariables, TupleSections, TypeOperators #-}
{-# LANGUAGE UnicodeSyntax #-}
{-# OPTIONS_GHC -Wall -Wno-unticked-promoted-constructors #-}
{-# OPTIONS_GHC -Wno-name-shadowing #-}

module HoloCanvas where

-- Basis
import           Prelude                           hiding ((.))
import           Prelude.Unicode
import           Control.Applicative.Free
import           Control.Lens

-- Type-level
import           GHC.Types
import           GHC.TypeLits                      hiding (Text)

-- Types
import           Control.Monad                            (when, forM_)
import           Control.Monad.IO.Class                   (MonadIO, liftIO)
import qualified Data.Map                          as Map
import qualified Data.Text                         as T
import qualified Data.Vector                       as V
import qualified Data.Vect                         as Vc
import           Data.Vect                                (Mat4(..), Vec3(..))
import           Numeric.Extra                            (doubleToFloat)

-- Algebra
import           Linear

-- Manually-bound Cairo
import qualified Graphics.Rendering.Cairo          as GRC
import qualified Graphics.Rendering.Cairo.Internal as GRCI

-- glib-introspection -based Cairo and Pango
import qualified GI.Cairo                          as GIC
import qualified GI.Pango                          as GIP

-- Dirty stuff
import qualified Data.IORef                        as IO
import qualified Foreign.C.Types                   as F
import qualified Foreign                           as F
import qualified System.Mem.Weak                   as SMem

-- …
import           Graphics.GL.Core33                as GL

-- LambdaCube
import qualified LambdaCube.GL                     as GL
import qualified LambdaCube.GL.Mesh                as GL
import qualified LambdaCube.Linear                 as LCLin
import           LambdaCube.Mesh                   as LC

-- LambdaCube Quake III
import           GameEngine.Utils                  as Q3

-- Local imports
import Flatland
import FlatDraw
import HoloFont
import HoloCairo
import qualified HoloCube                          as HC
import HoloSettings
import Space


-- | A Cairo-capable 'Drawable' to display on a GL 'Frame'.
data Drawable where
  Drawable ∷
    { dObjectStream ∷ HC.ObjectStream
    , dDi           ∷ Di Int
    , dSurfaceData  ∷ (F.Ptr F.CUChar, (Int, Int))
    , dCairo        ∷ Cairo
    , dGIC          ∷ GIC.Context
    --
    , dMesh         ∷ LC.Mesh
    , dGPUMesh      ∷ GL.GPUMesh
    , dGLObject     ∷ GL.Object
    , dTexId        ∷ GLuint
    } → Drawable

makeDrawable ∷ (MonadIO m) ⇒ HC.ObjectStream → Di Double → m Drawable
makeDrawable dObjectStream@HC.ObjectStream{..} dDi' = liftIO $ do
  let dDi@(Di (V2 w h)) = fmap ceiling dDi'
  dSurface      ← GRC.createImageSurface GRC.FormatARGB32 w h
  dCairo        ← cairoCreate  dSurface
  dGIC          ← cairoToGICairo dCairo

  let (dx, dy) = (fromIntegral w, fromIntegral $ -h)
      -- position = V.fromList [ LCLin.V3  0 dy 0, LCLin.V3  0  0 0, LCLin.V3 dx  0 0, LCLin.V3  0 dy 0, LCLin.V3 dx  0 0, LCLin.V3 dx dy 0 ]
      position = V.fromList [ LCLin.V2  0 dy,   LCLin.V2  0  0,   LCLin.V2 dx  0,   LCLin.V2  0 dy,   LCLin.V2 dx  0,   LCLin.V2 dx dy ]
      texcoord = V.fromList [ LCLin.V2  0  1,   LCLin.V2  0  0,   LCLin.V2  1  0,   LCLin.V2  0  1,   LCLin.V2  1  0,   LCLin.V2  1  1 ]
      dMesh    = LC.Mesh { mPrimitive  = P_Triangles
                         , mAttributes = Map.fromList [ ("position",  A_V2F position)
                                                      , ("uv",        A_V2F texcoord) ] }
  dGPUMesh      ← GL.uploadMeshToGPU dMesh
  SMem.addFinalizer dGPUMesh $
    GL.disposeMesh dGPUMesh
  dGLObject     ← GL.addMeshToObjectArray osStorage (HC.fromOANS osObjArray) [HC.unameStr osUniform, "viewProj"] dGPUMesh

  dSurfaceData  ← imageSurfaceGetPixels' dSurface
  dTexId        ← F.alloca $! \pto → glGenTextures 1 pto >> F.peek pto

  -- dTexture      ← uploadTexture2DToGPU'''' False False False False $ (fromWi dStridePixels, h, GL_BGRA, pixels)
  pure Drawable{..}

imageSurfaceGetPixels' :: GRC.Surface → IO (F.Ptr F.CUChar, (Int, Int))
imageSurfaceGetPixels' pb = do
  pixPtr ← GRCI.imageSurfaceGetData pb
  when (pixPtr ≡ F.nullPtr) $ do
    fail "imageSurfaceGetPixels: image surface not available"
  h ← GRC.imageSurfaceGetHeight pb
  r ← GRC.imageSurfaceGetStride pb
  return (pixPtr, (r, h))

drawableContentToGPU ∷ (MonadIO m) ⇒ Drawable → m ()
drawableContentToGPU Drawable{..} = liftIO $ do
  let HC.ObjectStream{..} = dObjectStream

  let (pixels, (strideBytes, pixelrows)) = dSurfaceData
  cTexture ← HC.uploadTexture2DToGPU'''' False False False False (strideBytes `div` 4, pixelrows, GL_BGRA, pixels) dTexId

  GL.updateObjectUniforms dGLObject $ do
    HC.fromUNS osUniform GL.@= return cTexture

-- | To screen space conversion matrix.
screenM :: Int → Int → Mat4
screenM w h =
  Vc.Mat4 (Vc.Vec4 (1/fw)  0     0 0)
          (Vc.Vec4  0     (1/fh) 0 0)
          (Vc.Vec4  0      0     1 0)
          (Vc.Vec4  0      0     0 0.5) -- where does that 0.5 factor COMEFROM?
  where (fw, fh) = (fromIntegral w, fromIntegral h)

framePutDrawable ∷ (MonadIO m) ⇒ HC.Frame → Drawable → Po Float → m ()
framePutDrawable (HC.Frame (Di (V2 screenW screenH))) Drawable{..} (Po (V2 x y)) = do
  let cvpos    = Vec3 x y 0
      toScreen = screenM screenW screenH
  liftIO $ GL.uniformM44F "viewProj" (GL.objectUniformSetter $ dGLObject) $
    Q3.mat4ToM44F $! toScreen Vc..*. (Vc.fromProjective $! Vc.translation cvpos)



-- * Very early generic widget code.
type DrawableSpace p d = Space             p Double d
type WidgetSpace     d = DrawableSpace False        d

class Show (StyleOf a) ⇒ Element a where
  type StyleOf a = (r ∷ Type) | r → a
  type Content a ∷ Type
  type Depth   a ∷ Nat

class Element w ⇒ Widget w where
  -- | Query size: style meets content → compute spatial parameters.
  query          ∷ (MonadIO m) ⇒ Settings PU           → StyleOf w → Content w → m (DrawableSpace False (Depth w))
  -- | Add target and space: given a drawable and a pinned space, prepare for 'render'.
  make           ∷ (MonadIO m) ⇒ Settings PU → CanvasW → StyleOf w → Content w →    DrawableSpace True  (Depth w) → m w
  -- | Per-content-change: mutate pixels of the bound drawable.
  draw           ∷ (MonadIO m) ⇒ CanvasW → w → m ()

class   Element w ⇒ Container w where
  type   Inner w ∷ Type
  innerOf        ∷ w → Inner w
  spaceToInner   ∷ w → DrawableSpace p (Depth w) → DrawableSpace p (Depth (Inner w))
  styleToInner   ∷ w → StyleOf w → StyleOf (Inner w)

class Container d ⇒ WDrawable d where
  assemble       ∷ (MonadIO m) ⇒ Settings PU → HC.ObjectStream → StyleOf d → Content d → m d
  drawableOf     ∷ d → Drawable
  render         ∷ (MonadIO m) ⇒ d → m ()


-- * Styles
-- Widget composition is inherently parametrized.
-- Different kinds of composition are parametrized differently.
-- Different instances of composition compose different kinds of widgets.
-- Applicative much?

data In o i where
  In ∷ --(Widget wo, Widget wi, StyleOf wo ~ o, StyleOf wi ~ i) ⇒ -- disabled by XXX/recursive pain
    { insideOf ∷ o
    , internal ∷ i
    } → In o i
deriving instance (Show o, Show i) ⇒ Show (In o i)

data By o b where
  By ∷ --(Widget wo, Widget wb, StyleOf wo ~ o, StyleOf wb ~ b) ⇒
    { bOrigin  ∷ o
    , bOrient  ∷ Orient Card
    , bBeside  ∷ b
    } → By o b
deriving instance (Show o, Show b) ⇒ Show (By o b)

data RRectS where
  RRectS ∷
    { rrCLBezel, rrCBorder, rrCDBezel, rrCBG ∷ Co Double
    , rrThBezel, rrThBorder, rrThPadding ∷ Th Double
    } → RRectS
deriving instance Show RRectS


-- * (): a null widget
instance Element () where
  type  StyleOf () = ()
  type  Content () = ()
  type    Depth () = 0
instance Widget () where
  query _settings        _style _content = pure End
  make  _settings CW{..} _style _content        End = pure ()
  draw            CW{..}                             _widget = pure ()

dpx ∷ Po Double → Co Double → GRCI.Render ()
dpx (Po (V2 x y)) (Co (V4 r g b a)) = GRC.setSourceRGBA r g b a >>
                                      -- GRC.rectangle (x) (y) 1 1 >> GRC.fill
                                      GRC.rectangle (x-1) (y-1) 3 3 >> GRC.fill


-- * Text
data TextS (u ∷ UnitK) where
  TextS ∷
    { tFontKey      ∷ FontKey
    , tMaxParaLines ∷ Int
    , tColor        ∷ Co Double
    } → TextS u
deriving instance Show (TextS u)

data Text where
  Text ∷
    { tPSpace       ∷ DrawableSpace True 1
    , tStyle        ∷ StyleOf Text
    , tFont         ∷ Font Bound PU
    , tLayout       ∷ GIP.Layout
    , tTextRef      ∷ IO.IORef T.Text
    } → Text

-- | Sets the text content of WText, but doesn't update its rendering.
wtextSetText ∷ (MonadIO m) ⇒ Text → T.Text → m ()
wtextSetText Text{..} textVal = liftIO $ IO.writeIORef tTextRef textVal

instance Element Text where
  type  StyleOf Text = TextS PU
  type  Content Text = T.Text
  type    Depth Text = 1
instance Widget Text where
  query Settings{..} TextS{..} initialText = do
    let Font{..} = lookupFont' fontmap tFontKey
    laySetMaxParaLines fDetachedLayout tMaxParaLines
    d ∷ Di (Dim PU) ← layRunTextForSize fDetachedLayout fDΠ defaultWidth initialText -- XXX/GHC/inference: weak
    pure $ mkSpace $ fromPU ∘ fromDim fDΠ <$> d
  make Settings{..} (CW (Canvas Drawable{..} _ _ tFont@FontBinding{..} _))
       tStyle@(TextS _ _ _) tText tPSpace = do
    tLayout  ← makeTextLayout fbContext
    tTextRef ← liftIO $ IO.newIORef tText
    pure Text{..}
  draw (CW (Canvas (Drawable{..}) _ _ _ _))
       (Text (Sarea area@(Parea _ ltp@(Po lt)))
             TextS{..}
             (FontBinding Font{..} _) lay textRef) = do
    let Po rb = pareaSE area
        dim   = rb ^-^ lt
    laySetSize         lay fDΠ $ Di (PUs <$> dim)
    laySetMaxParaLines lay tMaxParaLines
    layDrawText dCairo dGIC lay ltp tColor =<< (liftIO $ IO.readIORef textRef)
    -- let V2 w h = ceiling <$> dim ∷ V2 Int
    -- layDrawText dGRC dGIC lay (po 0 0) (coOpaq 1 0 0) $
    --   T.pack $ printf "sz %d %d" w h


-- * Rounded rectangle
data RRect a where
  RRect ∷
    { rrPSpace ∷ DrawableSpace True (Depth (RRect a))
    , rrStyle ∷ StyleOf (RRect a)
    , rrInner ∷ a
    } → RRect a
deriving instance (Show a, Show (StyleOf a)) ⇒ Show (RRect a)

instance Element a ⇒ Element (RRect a) where
  type             StyleOf (RRect a) = In RRectS (StyleOf a) -- XXX/recursive pain
  type             Content (RRect a) = Content a
  type               Depth (RRect a) = 4 + Depth a
instance Widget a ⇒ Container (RRect a) where
  type Inner (RRect a) = a
  innerOf                 = rrInner
  styleToInner _ (In _ s) = s
  spaceToInner _ (Spc _ (Spc _ (Spc _ (Spc _ s)))) = s

instance Widget a ⇒ Widget (RRect a) where
  query st@Settings{..} (In RRectS{..} inner) internals = do
    innerSpace ← query st inner internals
    pure $ (spaceGrow rrThBezel $ spaceGrow rrThBorder $ spaceGrow rrThBezel $ spaceGrow rrThPadding End)
           <> innerSpace
  make st@Settings{..} drawable rrStyle rrContent rrPSpace = do
    let w = RRect{..} where rrInner = (⊥)    -- resolve circularity due to *ToInner..
    make st drawable (styleToInner w rrStyle) rrContent (spaceToInner w rrPSpace) <&> (\x→ w { rrInner = x }) -- XXX/lens
  draw canvas@(CW (Canvas (Drawable _ _ _ dCairo _ _ _ _ _) _ _ _ _))
       (RRect (Spc obez (Spc bord (Spc ibez (Spc pad _))))
              (In RRectS{..} _) inner) = do
    runCairo dCairo $ do
      let -- dCorn (RRCorn _ pos _ _) col = d pos col
          ths@[oth, bth, ith, _]
                        = fmap (Th ∘ _wiV ∘ wThL) [obez, bord, ibez, pad]
          totpadx       = sum ths
          or            =       R ∘ _thV $ (totpadx - oth/2)
          br            = or - (R ∘ _thV $ (oth+bth)*0.6)
          ir            = br - (R ∘ _thV $ (bth+ith)/2)
      -- coSetSourceColor (co 0 1 0 1) >> GRC.paint
      -- background & border arcs
      let [n, ne, _, se, _, sw, _, nw] = wrapRoundedRectFeatures bord br bth
      GRC.newPath >> thLineSet bth
      forM_ [n, ne, se, sw, nw] $ executeFeature Nothing Nothing
      coSetSourceColor rrCBG >>
        GRC.fillPreserve
      coSetSourceColor rrCBorder >>
        GRC.stroke

      thLineSet oth -- border bezels: light outer TL, dark outer SE
      let [n, ne, e, se, s, sw, w, nw] = wrapRoundedRectFeatures obez or oth
      GRC.newPath
      (coSetSourceColor $ rrCLBezel) >>
        (forM_ [w, nw, n] $ executeFeature Nothing Nothing) >> GRC.stroke
      (coSetSourceColor $ rrCDBezel) >>
        (forM_ [e, se, s] $ executeFeature Nothing Nothing) >> GRC.stroke
      (coSetSourceColor $ rrCBorder) >>
        GRC.newPath >> (executeFeature (Just rrCDBezel) (Just rrCLBezel) sw) >> GRC.stroke >>
        GRC.newPath >> (executeFeature (Just rrCLBezel) (Just rrCDBezel) ne) >> GRC.stroke

      thLineSet ith -- border bezels: dark inner TL, light inner SE
      let [n, ne, e, se, s, sw, w, nw] = wrapRoundedRectFeatures ibez ir ith
      GRC.newPath
      (coSetSourceColor $ rrCDBezel) >>
        (forM_ [w, nw, n] $ executeFeature Nothing Nothing) >> GRC.stroke
      (coSetSourceColor $ rrCLBezel) >>
        (forM_ [e, se, s] $ executeFeature Nothing Nothing) >> GRC.stroke
      (coSetSourceColor $ rrCBorder) >>
        GRC.newPath >> (executeFeature (Just rrCLBezel) (Just rrCDBezel) sw) >> GRC.stroke >>
        GRC.newPath >> (executeFeature (Just rrCDBezel) (Just rrCLBezel) ne) >> GRC.stroke

       ∷ GRCI.Render () -- XXX/GHC: an apparent type checker bug
      -- ellipsized ← GIP.layoutIsEllipsized gip
      -- (, ellipsized) <$> GIP.layoutGetPixelSize gip
    draw canvas inner


-- * Canvas
--
-- Canvas is associated with a physical drawable surface.
data CanvasS (u ∷ Unit) where
  CanvasS ∷
    { cFontKey      ∷ FontKey
    } → CanvasS u
deriving instance Show (CanvasS u)

data Canvas a where
  Canvas ∷
    { cDrawable     ∷ Drawable
    , cPSpace       ∷ DrawableSpace True (Depth a)
    , cStyle        ∷ StyleOf (Canvas a)
    , cFont         ∷ Font Bound PU
    , cInner        ∷ a
    } → Canvas a
data CanvasW where
  CW ∷ Widget a ⇒ { cPoly ∷ Canvas a } → CanvasW

instance Widget a ⇒ Element (Canvas a) where
  type             StyleOf (Canvas a) = In (CanvasS PU) (StyleOf a)
  type             Content (Canvas a) = Content a
  type             Depth   (Canvas a) = Depth a
instance Widget a ⇒ Container (Canvas a) where
  type                  Inner (Canvas a) = a
  innerOf                   = cInner
  styleToInner   _ (In _ s) = s
  spaceToInner   _       s  = s

instance Widget a ⇒ WDrawable (Canvas a) where
  assemble settings@Settings{..} stream cStyle@(In (CanvasS cFontKey) innerStyle) innerContent = do
    cPSpace   ← spacePin (po 0 0) <$> query settings innerStyle innerContent
    cDrawable ← makeDrawable stream $ spaceDim cPSpace
    cFont     ← bindFont (lookupFont' fontmap cFontKey) $ dGIC cDrawable
    let w = Canvas{..} where cInner = (⊥)                -- resolve circularity due to *ToInner..
    cInner ← make settings (CW w) innerStyle innerContent cPSpace
    pure w { cInner = cInner }
  drawableOf = cDrawable
  render self@Canvas{..} = do
    draw (CW self) cInner
    drawableContentToGPU cDrawable


-- * Distributor
--
-- Distributor provides distribution (placement).
class Distributor a where


placeCanvas ∷ (MonadIO m, Widget a) ⇒ Canvas a → HC.Frame → Po Double → m ()
placeCanvas c f = framePutDrawable f (drawableOf c) ∘ (doubleToFloat <$>)
