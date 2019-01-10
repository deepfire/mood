{-# OPTIONS_GHC -Wall -Wno-unticked-promoted-constructors -Wno-unused-imports -Wno-type-defaults -Wno-orphans -fconstraint-solver-iterations=0 #-}
--{-# OPTIONS_GHC -ddump-deriv          #-} -- +
--{-# OPTIONS_GHC -ddump-rn             #-} -- +
--{-# OPTIONS_GHC -ddump-tc-trace       #-} -- +
--{-# OPTIONS_GHC -ddump-tc             #-} -- -
--{-# OPTIONS_GHC -ddump-rule-firings   #-} -- -
--{-# OPTIONS_GHC -ddump-ds             #-} -- -
module Holotype where

import           Control.Arrow
import           Control.Monad
import           Control.Monad.Fix
import           Control.Monad.Primitive
import           Control.Monad.Ref
import           Data.Foldable
import           Data.Functor.Misc                        (Const2(..))
import           Data.Maybe
import           Data.Semigroup
import           Data.Singletons
import           Data.Text                                (Text)
import           Data.Text.Zipper                         (TextZipper)
import           Data.Tuple
import           Data.Typeable
import           Generics.SOP.Monadic
-- import           GHC.IOR
import           Linear                            hiding (trace)
import           Prelude                           hiding (id, Word)
import           Reflex                            hiding (Query, Query(..))
import           Reflex.Host.Class                        (ReflexHost, MonadReflexHost)
import           Reflex.GLFW                              (RGLFW, RGLFWGuest, InputU(..))
import           Text.Read
import qualified Codec.Picture                     as Juicy
import qualified Codec.Picture.Saving              as Juicy
import qualified Control.Concurrent.STM            as STM
import qualified Control.Monad.Ref
import qualified Data.ByteString.Lazy              as B
import qualified Data.Map.Strict                   as M
import qualified Data.Sequence                     as Seq
import qualified Data.Set                          as Set
import qualified Data.Text                         as T
import qualified Data.Text.Zipper                  as T
import qualified Data.Time.Clock                   as Time
import qualified Data.TypeMap.Dynamic              as TM
import qualified Data.IntUnique                    as U
import qualified GHC.Generics                      as GHC
import qualified Graphics.GL.Core33                as GL
import qualified Options.Applicative               as Opt
import qualified Reflex.GLFW                       as GLFW
import qualified Text.Parser.Char                  as P
import qualified Text.Parser.Combinators           as P
import qualified Text.Parser.Token                 as P
import qualified Text.Trifecta.Parser              as P
import qualified Text.Trifecta.Result              as P

-- Local imports
import           Elsewhere
import qualified Graphics.Cairo                    as Cr
import           Graphics.Flatland
import qualified Graphics.Flex                     as Flex

import           Holo.Prelude                      hiding ((<>))
import           Holo.Classes
import           Holo.Instances
import           Holo.Input
import           Holo.Item
import           Holo.Name
import           Holo.Record
import           Holo.Widget                              ( Vocab, Definition(..), desNDen, desDen, traceVocab
                                                          , dynWidget, liftPureDynamic
                                                          , Blank
                                                          , Result(..), Widget, WH, stripW, wValD)
import qualified Holo.Widget                       as Widget
import qualified Holo.Port                         as Port
import           Holo.Port                                (Port(..), IdToken)
import qualified Holo.System                       as HOS

-- TEMPORARY
import           Generics.SOP                             (Proxy, Top)
import qualified Generics.SOP                      as SOP
import qualified "GLFW-b" Graphics.UI.GLFW         as GLFW


newPortFrame ∷ RGLFW t m ⇒ Event t VPort → m (Event t (VPort, Port.Frame))
newPortFrame portFrameE = performEvent $ portFrameE <&>
  \port@Port{..}→ do
    newFrame ← Port.portNextFrame port
    pure (port, newFrame)

type Avg a = (Int, Int, [a])
avgStep ∷ Fractional a ⇒ a → (a, Avg a) → (a, Avg a)
avgStep x (_, (lim, cur, xs)) =
  let (ncur, nxs) = if cur < lim
                    then (cur + 1, x:xs)
                    else (lim,     x:Prelude.init xs)
  in ((sum nxs) / fromIntegral ncur, (lim, ncur, nxs))

average ∷ (Fractional a, RGLFW t m) ⇒ Int → Event t a → m (Dynamic t a)
average n e = (fst <$>) <$> foldDyn avgStep (0, (n, 0, [])) e


-- mkTextEntryStyleD ∷ RGLFW t m ⇒ InputEventMux t → Behavior t (Style Text) → Text → m (W t (Text, HoloBlank))
-- mkTextEntryStyleD mux styleB initialV = do
--   tokenV       ← newId
--   let editE = select mux $ Const2 tokenV
--   valD         ← liftDyn initialV editE
--   setupE       ← getPostBuild
--   let holoE     = attachWith (leafStyled tokenV) styleB $ leftmost [updated valD, initialV <$ setupE]
--   holdDyn (initialV, emptyHolo) (attachPromptlyDyn valD holoE)
--    <&> (,) editMaskKeys

mkTextEntryValidatedStyleD ∷ ∀ i t m. HGLFW i t m ⇒ LBinds → Input t → Behavior t (Style TextLine) → Text → (Text → Bool) → m (Result i Text)
mkTextEntryValidatedStyleD lbs input styleB initialV testF = do
  unless (testF initialV) $
    error $ "Initial value not accepted by test: " <> T.unpack initialV
  -- (subD, textD) ← mkTextEntryStyleD mux styleB initialV
  Widget' (_, subD, itemD, textD) ← widget @i @Text lbs input (desDen @Text TextLine) initialV
  initial ← sample $ current textD
  foldDyn (\new oldValid→
               if testF new then new else oldValid)
    initial (updated textD)
    <&> Widget' ∘ (lbsAE lbs, subD,itemD,)

vboxD ∷ ∀ i t m. (HGLFW i t m) ⇒ Input t → [WH i] → ListenerBinds → m (Widget.FH i)
vboxD input chi lbs = do
  let (subsD, chiD) = foldr (\(sae, s, hb) (ss, hbs)→
                               ( zipDynWith (<>)
                                 (let LBinds (_,subs,_) = childBinds lbs sae
                                  in s subs)
                                 ss
                               , zipDynWith (:) hb hbs ))
                      (constDyn mempty, constDyn [])
                      chi
  pure $ (lbsAE lbs, subsD, vbox <$> chiD)



fpsCounterD ∷ RGLFW t m ⇒ Event t Port.Frame → m (Dynamic t Double)
fpsCounterD frameE = do
  frameMomentE     ← performEvent $ fmap (\_ → HOS.fromSec <$> HOS.getTime) frameE
  frameΔD          ← (fst <$>) <$> foldDyn (\y (_,x)->(y-x,y)) (0,0) frameMomentE
  avgFrameΔD       ← average 300 $ updated frameΔD
  pure (recip <$> avgFrameΔD)

nextFrame ∷ RGLFW t m ⇒ GLFW.Window → Event t () → m (Event t ())
nextFrame win windowFrameE = performEvent $ windowFrameE <&>
  \_ → liftIO $ do
    GLFW.swapBuffers win
    -- GL.flush  -- not necessary, but someone recommended it
    GLFW.pollEvents

trackStyle ∷ (As a, RGLFW t m) ⇒ Dynamic t (Sty a) → m (Dynamic t (Style a))
trackStyle sof = do
  gene ← count $ updated sof
  pure $ zipDynWith Style sof (StyleGene ∘ fromIntegral <$> gene)



instance Typeable a ⇒ Mutable   (Port.ScreenDim a)
instance Typeable a ⇒ Widgety i (Port.ScreenDim a)

instance SOP.Generic         Cr.FontPreferences
instance SOP.HasDatatypeInfo Cr.FontPreferences

(<:) ∷ Typeable b ⇒ TM.TypeMap a → (Proxy b, TM.Item a b) → TM.TypeMap a
(<:) tm (k, v) = TM.insert k v tm

defVocab ∷ Vocab i (Present i)
defVocab = Vocab
  (TM.empty
    <: (Proxy @Bool,             Desig TextLine)
    <: (Proxy @Bool,             DesigDenot Switch)
    <: (Proxy @Port.WaitVSync,   Desig Switch)
    <: (Proxy @Double,           Desig TextLine)
    <: (Proxy @DΠ,               Desig TextLine)
    <: (Proxy @Port.ScreenMode,  Desig TextLine)
    <: (Proxy @Float,            Desig TextLine)
    <: (Proxy @Int,              Desig TextLine)
    <: (Proxy @Integer,          Desig TextLine)
    <: (Proxy @Text,             DesigDenot TextLine)
    -- XXX:  this is atrocious, but the suspicion is we have a generic solution : -
    <: (Proxy @([(Cr.FontKey,(Either Cr.FontAlias [Cr.FontSpec]))])
       ,                         Desig TextLine)
    -- <: (Proxy @(Port.ScreenDim (Di Int)),
    --                              HoloName TextLine)
  )
deriving newtype instance Read DΠ
deriving         instance Read Port.ScreenMode
deriving newtype instance Read Cr.FontKey
deriving newtype instance Read Cr.FontAlias
deriving newtype instance Read Cr.FaceName
deriving newtype instance Read Cr.FamilyName
deriving         instance Read Cr.FontSizeRequest
deriving         instance Read Cr.FontSpec
deriving         instance Read WUnit
instance                  Read (Unit PU) where
  readPrec = prec 10 $ do
    Ident "PU" <- lexP
    m <- step readPrec
    return (PUs m)
instance                  Read (Unit PUI) where
  readPrec = prec 10 $ do
    Ident "PUI" <- lexP
    m <- step readPrec
    return (PUIs m)
instance                  Read (Unit Pt) where
  readPrec = prec 10 $ do
    Ident "Pt" <- lexP
    m <- step readPrec
    return (Pts m)

scene ∷ ∀ i t m. ( HGLFW i t m
                 , Typeable t)
  ⇒ Input t
  → Dynamic    t Port.Settings
  → Dynamic    t Integer
  → Dynamic    t Int
  → Dynamic    t Double
  → m (Widget.FH i)
scene input sttsD statsValD frameNoD fpsValueD = mdo

  fpsD ∷ Widget i Text
                   ← dynPresent "fps" input defVocab (T.pack ∘ printf "%3d fps" ∘ (floor ∷ Double → Integer) <$> fpsValueD)
  statsD ∷ Widget i Text
                   ← dynPresent "mem" input defVocab $ statsValD <&>
                     \(mem)→ T.pack $ printf "mem: %d" mem
  lolD ∷ Widget i Text
                   ← dynPresent "lol" input (desDen @Text $ Labelled ("mem", TextLine)) $ statsValD <&>
                     \(mem)→ T.pack $ printf "%d" mem

  let rectDiD       = (PUs <$>) ∘ join unsafe'di ∘ fromIntegral ∘ max 1 ∘ flip mod 200 <$> frameNoD
  rectD ∷ Widget i (Di (Unit PU))
                   ← liftPureDynamic "rect" Rect rectDiD

  frameCountD ∷ Widget i Text
                   ← dynPresent "nframes" input defVocab $ T.pack ∘ printf "frame #%04d" <$> frameNoD
  varlenTextD ∷ Widget i Text
                   ← dynPresent "truefalse" input defVocab $ T.pack ∘ printf "even: %s" ∘ show ∘ even <$> frameNoD

  doubleD ∷ Widget i Double
                   ← present "zero" input defVocab 0

  -- dimD ∷ Widget i (Double, Double)
  --                  ← liftW eV (X, (Labelled ("x", TextLine)
  --                                 ,Labelled ("y", TextLine)))
  --                    (0,0)

  tupleWD          ← present @i "tuple" input defVocab
                      (unsafe'di 320 200 ∷ Di Int)
  sttsWDCurr ∷ Widget i Port.Settings
                   ← dynPresent "Settings" input defVocab sttsD
  initSttsV        ← sample $ current sttsD
  sttsWDSeeded ∷ Widget i Port.Settings
                   ← present "settings-seed" input defVocab
                      -- (Cr.FontPreferences [])
                      initSttsV

  longStaticTextD  ← present @i "longstatictext" input (desDen @Text TextLine) ("0....5...10...15...20...25...30...35...40...45...50...55...60...65...70...75...80...85...90...95..100" ∷ Text)

  -- The loop demo (currently incapacitated due to definition of mkTextEntryValidatedStyleD)
  let fontNameStyle name = defSty (Proxy @TextLine) & tsFontKey .~ Cr.FK name
  styleNameD       ← mkTextEntryValidatedStyleD @i "stylename" input styleB "defaultSans" $
                     (\x→ x ≡ "defaultMono" ∨ x ≡ "defaultSans")
  styleD           ← trackStyle $ fontNameStyle <$> (traceDynWith show $ wValD styleNameD)
  let styleB        = current styleD

  --
  vboxD @i input
    [ stripW frameCountD
      -- , (snd <$>) <$> text2HoloQD
      -- , stripW styleNameD
      -- , stripW lolD
      -- , stripW doubleD
      -- , stripW recWD
    , stripW $ Widget.traceWVal "sttsWDCurr: " sttsWDCurr
      -- , stripW sttsWDSeeded
    , stripW tupleWD
      -- , stripW rectD
    , stripW fpsD
    , stripW longStaticTextD
    , stripW statsD
    , stripW varlenTextD
    ] $
    listenerBindsParse "Scene" (inStore input)
    [ ("Scene.Settings.sttsWaitVSync", "VSyncToggle")
    ]

instance SOP.Generic         (V2 a)
instance SOP.HasDatatypeInfo (V2 a)

deriving instance Generic    (Di a)
instance SOP.Generic         (Di a)
instance SOP.HasDatatypeInfo (Di a)

deriving instance Generic    (Port.ScreenDim (Di a))
instance SOP.Generic         (Port.ScreenDim (Di a))
instance SOP.HasDatatypeInfo (Port.ScreenDim (Di a))

instance Present i Port.WaitVSync
instance Widgety i Port.WaitVSync



data Options where
  Options ∷
    { oTrace ∷ Bool
    } → Options
parseOptions ∷ Opt.Parser Options
parseOptions =
  Options
  <$> Opt.switch (Opt.long "trace" <> Opt.help "[DEBUG] Enable allocation tracing")

holdDynMaybe ∷ (Reflex t, MonadHold t m, MonadFix m) ⇒ a → Event t (Maybe a) -> m (Dynamic t a)
holdDynMaybe initial ev = accumMaybeDyn (\_old mNew→ mNew) initial ev

-- * Top level network
--
holotype ∷ ∀ t m. (Typeable t) ⇒ RGLFWGuest t m
holotype win evCtl windowFrameE inputE = mdo
  Options{..} ← liftIO $ Opt.execParser $ Opt.info (parseOptions <**> Opt.helper)
                ( Opt.fullDesc
                  -- <> header   "A simple holotype."
                  <> Opt.progDesc "A simple holotype.")
  when oTrace $
    liftIO $ setupTracer False
    [(ALLOC,     TOK,  TRACE, 0),(FREE,      TOK, TRACE, 0)
    ,(SIZE,      HOLO, TRACE, 0)
    -- (ALLOC,     TOK, TRACE, 0),(FREE,      TOK, TRACE, 0)
    -- ,(MISSALLOC, VIS, TRACE, 4),(REUSE,     VIS, TRACE, 4),(REALLOC,   VIS, TRACE, 4),(ALLOC,     VIS, TRACE, 4),(FREE,        VIS, TRACE, 4)
    -- ,(ALLOC,     TEX, TRACE, 8),(FREE,      TEX, TRACE, 8)
    ]

  HOS.unbufferStdout

  initE            ← getPostBuild

  winD             ← holdDyn win $ win <$ initE
  initWinDimV      ← Port.portWindowSize win
  liftIO $ GLFW.enableEvent evCtl GLFW.FramebufferSize

  evE ∷ Event t Ev ← performEvent $ promoteEv <$> inputE

  -- Closing-the-circle issues:
  -- 1. To even receive events, the switch needs to be subscribed to <F3> -- but its subscriptions are default.
  -- 2. For #1 we need a way to express subscription customisation.
  -- 3. Tearing the Settings apart again to form ESettings?  ESettings looks way artificial now.
  -- 4. Should Settings even be a single structure?
  -- 5. EventBinding: Addresses (object names) to IdTokens.
  -- 6. Event is routed -- then interpreted how?  Currently event interpretation is hard-coded.
  -- 7. So we need names (and types) for events -- SemanticEvent (akin to WorldEvent).
  -- 8. Then we can express the problem: Named entities handling named events.
  -- 9. SemanticEvents, EventBindings and Addresses seem to be only needed during decision of how to compile subscriptions.
  -- 10. Objects declare SemanticEvents they can handle and their sub-Addresses.
  sttsE            ←
    let Port.Settings{sttsWaitVSync=Port.WaitVSync defvsync,..} = Port.defaultSettings
    in Port.ESettings
       <$> pure (initE $> (sttsDΠ, sttsFontPreferences))
       <*> pure (fforMaybe (leftmost [evE, Ev (WinSizeEv (Port.ScreenDim initWinDimV)) <$ initE])
                  (\case
                      Ev (WinSizeEv dim) → Just (sttsScreenMode, dim)
                      _ → Nothing))
       <*> pure (leftmost [Port.WaitVSync True <$ initE])
  sttsD            ← accumMaybeDyn (flip const) Port.defaultSettings $ (fmap Port.portSettings) <$> updated maybePortD

  maybePortD       ← Port.portCreate winD sttsE
  portFrameE       ← newPortFrame $ fmapMaybe id $ fst <$> attachPromptlyDyn maybePortD windowFrameE

  -- * Random data: stats
  fpsValueD        ← fpsCounterD $ snd <$> portFrameE
  frameNoD         ← count portFrameE
  statsValD        ← holdDyn 0 =<< performEvent (portFrameE <&> const HOS.gcKBytesUsed)

  -- * SCENE
  -- not a loop:  subscriptionsD only used/sampled during inputE, which is independent
  let inputEv       = fforMaybe inputE
                      (\case x@(U GLFW.EventMouseButton{}) → Just $ Ev $ GLFWEv x; _ → Nothing)
  inputMux         ← routeEv inputEv clickedE subscriptionsD
  (,,) _ae subscriptionsD sceneD
                   ← scene @(API t m) input sttsD statsValD frameNoD fpsValueD

  semStoreV        ← declSemStore "main"
    [ ("VSyncToggle"
      , "Toggle waiting for vertical synchronisation.")
    ]
  let input         = mkInput semStoreV evBindsD inputMux
      bind = bindSem semStoreV
      evBindsD      = constDyn $ mempty
        & bind "VSyncToggle" (inputMaskKeyPress GLFW.Key'F3 mempty)


  -- * LAYOUT
  -- needs port because of DPI and fonts
  sceneQueriedE    ← performEvent $ (\(s, (p, _f))→ iSizeRequest p s) <$>
                     attachPromptlyDyn sceneD portFrameE
  sceneQueriedD    ← holdDyn mempty sceneQueriedE

  let sceneLaidTreeD ∷ Dynamic t (Item Top PLayout)
      sceneLaidTreeD = Flex.layout (Size $ fromPU <$> di 800 600) <$> sceneQueriedD

  -- * RENDER
      sceneDrawE     = attachPromptlyDyn sceneLaidTreeD portFrameE
  drawnPortE       ← performEvent $ sceneDrawE <&>
                     \(tree, (,) port f@Port.Frame{..}) → do
                       -- let ppItem = \case
                       --       x@Node{..} → "N: "<>Flex.ppItemArea x<>" ← "<>Flex.ppItemSize x<>" geoΔ: "<>Flex.ppdefGeoDiff (iGeo x)
                       --       x@Leaf{..} → "L: "<>Flex.ppItemArea x<>" ← "<>Flex.ppItemSize x<>" geoΔ: "<>Flex.ppdefGeoDiff (iGeo x)
                       -- Flex.dump ppItem tree
                       let leaves = treeLeaves tree
                       -- liftIO $ printf "   leaves: %d\n" $ M.size leaves
                       Port.portGarbageCollectVisuals port leaves
                       tree' ← ensureTreeVisuals port tree
                       -- XXX: 'render' is called every frame for everything
                       renderTreeVisuals port tree'
                       showTreeVisuals f tree'
                       pure port
  drawnPortD       ← holdDyn Nothing $ Just <$> drawnPortE

  -- * PICKING
  let clickE        = ffilter (evMatch inputMaskClick1Press) evE
      pickE         = fmapMaybe id $ attachPromptlyDyn drawnPortD clickE <&> \case
                        (Nothing, _) → Nothing -- We may have no drawn picture yet.
                        (Just x, y)  → Just (x, y)
  clickedE         ← mousePointId $ (id *** (\(Ev (GLFWEv (U x@GLFW.EventMouseButton{})))→ x)) <$> pickE
  performEvent_ $ clickedE <&>
    \(ClickEv{..})→ liftIO $ printf "pick=0x%x\n" (Port.tokenHash ceIdToken)

  hold False (evMatch (inputMaskKeyPress' GLFW.Key'Escape)
               <$> evE)

mousePointId ∷ RGLFW t m ⇒ Event t (VPort, GLFW.Input 'GLFW.MouseButton) → m (Event t (Ev' ClickEvK))
mousePointId ev = (ffilter ((≢ 0) ∘ Port.tokenHash ∘ ceIdToken) <$>) <$>
                  performEvent $ ev <&> \(port@Port{..}, e@(GLFW.EventMouseButton _ _ _ _)) → do
                    (,) x y ← liftIO $ (GLFW.getCursorPos portWindow)
                    ClickEv e <$> (Port.portPick port $ floor <$> po x y)
