{-# LANGUAGE NoMonomorphismRestriction #-}
{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -Wall -Wno-unticked-promoted-constructors -Wno-orphans -Wno-type-defaults #-}
{-# OPTIONS_GHC -Wno-unused-imports -Wno-unused-top-binds #-}
module Graphics.Flatland
  ( WUnit(..), fromWUnit
  , Unit(..), UnitK(..), pu'val, pui'val, pt'val
  , FromUnit, FromUnit'(..), StandardUnit(..)
  --
  , DΠ(..)
  --
  , V2A(..), v2a, v2a'lift, v2'proj
  , ppV2
  --
  , An(..), an'val
  , An2(..), an2
  , Po(..), po, po'd, po'add, po'sub
  , Di(..), di, di'd, di'v, unsafe'di, diNothing
  , Wi(..), wi'val, He(..), he'val, Th(..), th'val
  , Pad(..), pad'val, Mgn(..), mgn'val
  , Co(..), co, coMult
  , LU(..), RB(..), lu'po, rb'po
  , R(..), r'val
  , Cstr(..), Reqt(..), Size(..), Orig(..), reqt'add, size'd, size'di
  , Axis(..), Minor(..), Major(..)
  , Orient(..), OKind(..)
  , Area, Area'(..), Area'Orig, Area'LU, Area'LURB, FromArea(..), HasArea(..)
  , area'a, area'b
  , pretty'Area'Int
  , area'split'start, area'split'end
  --
  , opaque, white, gray, black
  , base03, base02, base01, base00, base0, base1, base2, base3, yellow, orange, red, magenta, violet, blue, cyan, green
  , chord'CW
  )
where
import qualified Text.Read                         as TR
import qualified Data.Map.Strict                   as Map
import qualified Data.Text.Format                  as T
import qualified Data.Text.Lazy                    as TL
import qualified Foreign                           as F
import qualified GI.Pango                          as GIP (unitsToDouble, unitsFromDouble)
import qualified Generics.SOP                      as SOP
import qualified System.IO.Unsafe                  as UN

import           ExternalImports
import           Elsewhere


-- * Dimensional density.
newtype PΠ = PΠ { pπVal ∷ Double } deriving (Num, Show)
pπ ∷ PΠ
pπ = 72

newtype DΠ = DΠ { fromDΠ ∷ Double } deriving (Eq, Num, Show)
deriving newtype instance Read DΠ

-- $Note [Pango resolution & unit conversion]
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
--   > Sets the resolution for the fontmap. This is a scale factor between
--   > points specified in a #PangoFontDescription and Cairo units. The
--   > default value is 96, meaning that a 10 point font will be 13
--   > units high. (10 * 96. / 72. = 13.3).
--   cited from: https://git.gnome.org/browse/pango/tree/pango/pangocairo-fontmap.c#n236
--   I.e.:
--     units  = points ⋅ dπ / pπ
--     points = units  / dπ ⋅ pπ
--
--   A good situation report is also at:
--     https://mail.gnome.org/archives/gtk-i18n-list/2002-May/msg00004.html
--
-- double pango_units_to_double   (int i)    { return (double)i / PANGO_SCALE; }
-- int    pango_units_from_double (double d) { return (int)floor (d * PANGO_SCALE + 0.5); }


-- * Universal, multi-density linear size.

data UnitK = PU | PUI | Pt
$(genSingletons [''UnitK])

type instance Element (Unit PU)   = Double
type instance Element (Unit PUI)  = F.Int32
type instance Element (Unit Pt)   = F.Int32

deriving         instance Read WUnit
instance                  Read (Unit PU) where
  readPrec = TR.prec 10 $ do
    TR.Ident "PU" <- TR.lexP
    m <- TR.step TR.readPrec
    return (PUs m)
instance                  Read (Unit PUI) where
  readPrec = TR.prec 10 $ do
    TR.Ident "PUI" <- TR.lexP
    m <- TR.step TR.readPrec
    return (PUIs m)
instance                  Read (Unit Pt) where
  readPrec = TR.prec 10 $ do
    TR.Ident "Pt" <- TR.lexP
    m <- TR.step TR.readPrec
    return (Pts m)

class StandardUnit (a ∷ UnitK → Type) where
  convert ∷ (FromUnit u, FromUnit v) ⇒ DΠ → a u → a v

data Unit (u ∷ UnitK) where
  PUs    ∷ { fromPU    ∷ !(Element (Unit PU))    } → Unit PU    -- ^ Pango size, in device units -- aka pixels, as evidence overwhelmingly points to
  PUIs   ∷ { fromPUI   ∷ !(Element (Unit PUI))   } → Unit PUI   -- ^ Pango size, in device units, scaled by PANGO_SCALE
  Pts    ∷ { fromPt    ∷ !(Element (Unit Pt))    } → Unit Pt    -- ^ Pango size, in points (at 72ppi--see PΠ above--rate), device-agnostic
type family UnitType a = r | r → a where
  UnitType (Unit PU)    = PU
  UnitType (Unit PUI)   = PUI
  UnitType (Unit Pt)    = Pt

data WUnit where
  UnitPU  ∷ Unit PU  → WUnit
  UnitPUI ∷ Unit PUI → WUnit
  UnitPt  ∷ Unit Pt  → WUnit
  deriving (Eq, Generic)
instance Show WUnit where
  show (UnitPU  a) = show a
  show (UnitPUI a) = show a
  show (UnitPt  a) = show a
instance SOP.Generic         WUnit
instance SOP.HasDatatypeInfo WUnit



pu'val  ∷ Lens' (Unit PU)  (Element (Unit PU))
pu'val  f (PUs x)  = PUs  <$> f x
pui'val ∷ Lens' (Unit PUI) (Element (Unit PUI))
pui'val f (PUIs x) = PUIs <$> f x
pt'val  ∷ Lens' (Unit Pt)  (Element (Unit Pt))
pt'val  f (Pts x)  = Pts  <$> f x

-- <Boilerplate>
deriving instance Eq   (Unit u)
deriving instance Show (Unit u)
instance Fractional (Unit PU) where
  fromRational x = PUs $ fromRational x
  recip          = omap recip
instance MonoFunctor (Unit PU)    where omap f (PUs    x) = PUs    (f x)
instance MonoFunctor (Unit PUI)   where omap f (PUIs   x) = PUIs   (f x)
instance MonoFunctor (Unit Pt)    where omap f (Pts    x) = Pts    (f x)
instance Ord (Unit PU)    where PUs    l <= PUs    r = l <= r
instance Ord (Unit PUI)   where PUIs   l <= PUIs   r = l <= r
instance Ord (Unit Pt)    where Pts    l <= Pts    r = l <= r
instance Num (Unit PU)    where fromInteger = PUs    ∘ fromIntegral; PUs    x + PUs    y = PUs    $ x + y; PUs    x * PUs    y = PUs    $ x * y; abs = omap abs; signum = omap signum; negate = omap negate
instance Num (Unit PUI)   where fromInteger = PUIs   ∘ fromIntegral; PUIs   x + PUIs   y = PUIs   $ x + y; PUIs   x * PUIs   y = PUIs   $ x * y; abs = omap abs; signum = omap signum; negate = omap negate
instance Num (Unit Pt)    where fromInteger = Pts    ∘ fromIntegral; Pts    x + Pts    y = Pts    $ x + y; Pts    x * Pts    y = Pts    $ x * y; abs = omap abs; signum = omap signum; negate = omap negate

instance Random (Unit PU) where
  randomR (PUs a, PUs a')   = runState $ liftA PUs $ state $ randomR (a, a')
  random                    = runState $ liftA PUs $ state random
instance Random (Unit PUI) where
  randomR (PUIs a, PUIs a') = runState $ liftA PUIs $ state $ randomR (a, a')
  random                    = runState $ liftA PUIs $ state random
instance Random (Unit Pt) where
  randomR (Pts a, Pts a')   = runState $ liftA Pts $ state $ randomR (a, a')
  random                    = runState $ liftA Pts $ state random
instance Random a ⇒ Random (V2 a) where
  randomR (V2 x y, V2 x' y') = runState $ liftA2 V2 (state $ randomR (x, x')) (state $ randomR (y, y'))
  random                     = runState $ liftA2 V2 (state random) (state random)
instance Random a ⇒ Random (V3 a) where
  randomR (V3 x y z, V3 x' y' z') = runState $ liftA3 V3 (state $ randomR (x, x')) (state $ randomR (y, y')) (state $ randomR (z, z'))
  random                          = runState $ liftA3 V3 (state random) (state random) (state random)
instance Random a ⇒ Random (V4 a) where
  randomR (V4 x y z w, V4 x' y' z' w') = runState $ V4 <$> (state $ randomR (x, x')) <*> (state $ randomR (y, y')) <*> (state $ randomR (z, z')) <*> (state $ randomR (w, w'))
  random                               = runState $ V4 <$> (state random) <*> (state random) <*> (state random) <*> (state random)
-- </Boilerplate>

-- | Conversion between unit sizes -- See Note [Pango resolution & unit conversion]
-- class a ~ (Unit (UnitType a)) ⇒ FromUnit a where
--   fromUnit ∷ FromUnit b ⇒ DΠ → b → a
class (Eq a, Ord a) ⇒ FromUnit' a where
  fromUnit ∷ FromUnit' (Unit b) ⇒ DΠ → Unit b → a

fromWUnit ∷ FromUnit' a ⇒ DΠ → WUnit → a
fromWUnit dπ (UnitPU  x) = fromUnit dπ x
fromWUnit dπ (UnitPUI x) = fromUnit dπ x
fromWUnit dπ (UnitPt  x) = fromUnit dπ x

type FromUnit u = FromUnit' (Unit u)

instance FromUnit' (Unit PU) where
  fromUnit _       x@(PUs _)    = x
  fromUnit _         (PUIs pis) = PUs $ UN.unsafePerformIO ∘ GIP.unitsToDouble   $ pis -- fromIntegral pis / fromIntegral GIP.SCALE
  fromUnit (DΠ dπ)   (Pts pts)  = PUs $ (fromIntegral pts) ⋅ dπ / pπVal pπ
instance FromUnit' (Unit PUI) where
  fromUnit _       x@(PUIs _)   = x
  fromUnit _         (PUs pus)  = PUIs $ UN.unsafePerformIO ∘ GIP.unitsFromDouble $ pus -- floor $ pus ⋅ fromIntegral GIP.SCALE
  fromUnit (DΠ dπ)   (Pts pts)  = PUIs $ UN.unsafePerformIO ∘ GIP.unitsFromDouble $ fromIntegral pts ⋅ dπ / pπVal pπ
instance FromUnit' (Unit Pt) where
  fromUnit _       x@(Pts _)    = x
  fromUnit (DΠ dπ)   (PUs pus)  = Pts $ floor $                                                                 pus ⋅ pπVal pπ / dπ
  fromUnit (DΠ dπ)   (PUIs pis) = Pts $ floor $ UN.unsafePerformIO ∘ GIP.unitsToDouble ∘ floor $ (fromIntegral pis) ⋅ pπVal pπ / dπ


-- * Specialized linear dimension classification:

infinity ∷ Double
infinity = read "Infinity"

newtype R   a = R   { _r'val  ∷ a }  deriving (Eq, Fractional, Functor, Num) -- ^ Radius
newtype An  a = An  { _an'val ∷ a }  deriving (Eq, Fractional, Functor, Num) -- ^ Angle
newtype Th  a = Th  { _th'val ∷ a }  deriving (Eq, Fractional, Functor, Num) -- ^ Thickness
newtype He  a = He  { _he'val ∷ a }  deriving (Eq, Fractional, Functor, Num) -- ^ Height
newtype Wi  a = Wi  { _wi'val ∷ a }  deriving (Eq, Fractional, Functor, Num) -- ^ Width
newtype Pad a = Pad { _pad'val ∷ a } deriving (Eq, Fractional, Functor, Num) -- ^ Padding
newtype Mgn a = Mgn { _mgn'val ∷ a } deriving (Eq, Fractional, Functor, Num) -- ^ Margin
instance Applicative R  where pure = R;  R  f <*> R  x = R  $ f x
instance Applicative An where pure = An; An f <*> An x = An $ f x
instance Applicative Th where pure = Th; Th f <*> Th x = Th $ f x
instance Applicative He where pure = He; He f <*> He x = He $ f x
instance Applicative Wi where pure = Wi; Wi f <*> Wi x = Wi $ f x
instance Applicative Pad where pure = Pad; Pad f <*> Pad x = Pad $ f x
instance Applicative Mgn where pure = Mgn; Mgn f <*> Mgn x = Mgn $ f x
instance Additive R  where zero = R  0
instance Additive An where zero = An 0
instance Additive Th where zero = Th 0
instance Additive He where zero = He 0
instance Additive Wi where zero = Wi 0
instance Additive Pad where zero = Pad 0
instance Additive Mgn where zero = Mgn 0
deriving instance Foldable R
deriving instance Foldable An
deriving instance Foldable Th
deriving instance Foldable He
deriving instance Foldable Wi
deriving instance Foldable Pad
deriving instance Foldable Mgn
-- instance Metric …  where ?
deriving instance Show a ⇒ Show (R  a)
deriving instance Show a ⇒ Show (An a)
deriving instance Show a ⇒ Show (Th a)
deriving instance Show a ⇒ Show (He a)
deriving instance Show a ⇒ Show (Wi a)
deriving instance Show a ⇒ Show (Pad a)
deriving instance Show a ⇒ Show (Mgn a)
deriving instance Random a ⇒ Random (R a)
deriving instance Random a ⇒ Random (An a)
deriving instance Random a ⇒ Random (Th a)
deriving instance Random a ⇒ Random (He a)
deriving instance Random a ⇒ Random (Wi a)
deriving instance Random a ⇒ Random (Pad a)
deriving instance Random a ⇒ Random (Mgn a)
makeLenses ''R
makeLenses ''An
makeLenses ''Th
makeLenses ''He
makeLenses ''Wi
makeLenses ''Pad
makeLenses ''Mgn


-- * Pairing dimensions:
--
-- XXX: HUGE NOTE: V2/Co/Wrap mass of code below is likely silliness,
--      easily replaced with a couple of short lens operators.
--      Nevertheless, it is what it is -- because of blissful lack of education.
--      Typical.
--
-- In particular, this screams for Linear.Affine
--
newtype  Di a =  Di { _di'v  ∷ V2 a }      deriving (Additive, Applicative, Eq, Fractional, Functor, Num) -- ^ Dimensions
newtype  Po a =  Po { _po'v  ∷ V2 a }      deriving (Additive, Applicative, Eq, Fractional, Functor, Num) -- ^ Coordinates, Descartes
newtype RPo a = RPo { _rpo'v ∷ Complex a } deriving (Additive, Applicative, Eq, Fractional, Functor, Num) -- ^ Coordinates, polar

-------- <boilerplate>
deriving instance Show a ⇒ Show  (Di a); deriving instance Show a ⇒ Show  (Po a); deriving instance Show a ⇒ Show  (RPo a)
deriving instance (Ord a) ⇒ HasLub (Di a)
deriving instance (Ord a) ⇒ HasGlb (Di a)
deriving instance (Ord a) ⇒ HasLub (Po a)
deriving instance (Ord a) ⇒ HasGlb (Po a)
newtype An2 a = An2 { _an2V ∷ V2 a } deriving (Eq, Applicative, Functor) -- ^ Unordered pair of angles
newtype Co  a = Co  { _coV  ∷ V4 a } deriving (Eq, Applicative, Functor) -- ^ Color
deriving instance Show a ⇒ Show (An2 a)
deriving instance Show a ⇒ Show (Co a)
deriving instance Random a ⇒ Random (Di a)
deriving instance Random a ⇒ Random (Po a)
deriving instance Random a ⇒ Random (RPo a)
deriving instance Random a ⇒ Random (Co a)
deriving instance Random a ⇒ Random (An2 a)

-- XXX: -ddump-deriv this:
-- deriving instance Monoid a ⇒ Monoid (Di a)
instance Num a ⇒ Semigroup (Di a) where
  Di l <> Di r = Di $ l + r
instance Num a ⇒ Monoid    (Di a) where
  mempty              = Di zero

instance (Fractional a) ⇒ Semigroup (Po a) where
  Po l <> Po r = Po $ (l + r) / 2
instance (Fractional a) ⇒ Monoid    (Po a) where
  mempty              = Po zero

-- instance Applicative RPo where pure x = RPo (R x, An x); RPo (R fr, An fan) <*> RPo (R r, An an) = RPo (R $ fr r, An $ fan an)
-- instance Additive    RPo where zero = RPo (zero, zero)
-- instance Num a ⇒ Num (RPo a) where
--   (+) = liftA2 (+)

makeLenses ''Di
makeLenses ''Po
makeLenses ''RPo
makeLenses ''An2
makeLenses ''Co

ppV2 ∷ Show a ⇒ V2 a → TL.Text
ppV2 x = (TL.pack ∘ show $ x^._x) <> "x" <> (TL.pack ∘ show $ x^._y)

instance Show a ⇒ Pretty (Di a) where pretty = pretty ∘ ("#<Di " <>) ∘ (<> ">") ∘ ppV2 ∘ (^.di'v)
instance Show a ⇒ Pretty (Po a) where pretty = pretty ∘ ("#<Po " <>) ∘ (<> ">") ∘ ppV2 ∘ (^.po'v)
---------- </boilerplate>

unsafe'di ∷ a → a → Di a
unsafe'di x y = Di $ V2 x y
{-# INLINE unsafe'di #-}

di ∷ Wi a → He a  → Di a
di  (Wi x) (He y) = Di $ V2 x y
{-# INLINE di #-}

po ∷ a → a → Po a
po x y = Po $ V2 x y
{-# INLINE po #-}

rpo ∷ Floating a ⇒ R a → An a → RPo a
rpo (R r) (An a) = RPo (mkPolar r a)
{-# INLINE rpo #-}

an2 ∷ a → a → An2 a
an2 x y = An2 $ V2 x y
{-# INLINE an2 #-}

co ∷ a → a → a → a → Co a
co r g b a = Co $ V4 r g b a
{-# INLINE co #-}

diNothing ∷ Di (Maybe a)
diNothing = unsafe'di Nothing Nothing
{-# INLINE diNothing #-}

infinite ∷ Di Double
infinite = Di $ V2  infinity infinity
{-# INLINE infinite #-}

po2rpo ∷ Po a → RPo a
po2rpo (Po (V2 x y))  = RPo $ x :+ y
rpo2po ∷ RPo a → Po a
rpo2po (RPo (x :+ y)) = Po $ V2 x y

rotateRPo ∷ RealFloat a ⇒ An a → RPo a → RPo a
rotateRPo (An a) (RPo c) = RPo $ mkPolar (magnitude c) (phase c + a)

po'add, po'sub ∷ Num a ⇒ V2 a → Po a → Po a
po'add v _po = Po (_po'v _po ^+^ v)
po'sub v _po = Po (_po'v _po ^-^ v)
{-# INLINE po'add #-}
{-# INLINE po'sub #-}

poDelta ∷ Num a ⇒ Po a → Po a → Di a
poDelta (Po v) (Po v') = Di $ v ^-^ v'

goldXdi ∷ RealFrac a ⇒ Wi a → Di a
goldXdi (Wi x) = Di $ V2  x (x / realToFrac goldenRatio)
goldYdi ∷ RealFrac a ⇒ He a → Di a
goldYdi (He y) = Di $ V2 (y / realToFrac goldenRatio) y

di'd   ∷ Axis → Lens' (Di a) a
di'd   X f (Di (V2 x y)) = Di ∘ (flip V2 y) <$> f x
di'd   Y f (Di (V2 x y)) = Di ∘ (id   V2 x) <$> f y
po'd   ∷ Axis → Lens' (Po a) a
po'd   X f (Po (V2 x y)) = Po ∘ (flip V2 y) <$> f x
po'd   Y f (Po (V2 x y)) = Po ∘ (id   V2 x) <$> f y

di'w ∷ Lens' (Di a) (Wi a)
di'h ∷ Lens' (Di a) (He a)
di'w f (Di (V2 x y)) = Di ∘ (flip V2 y) ∘ _wi'val <$> f (Wi x)
di'h f (Di (V2 x y)) = Di ∘       V2 x  ∘ _he'val <$> f (He y)


-- * Colors
--
instance Semigroup (Co Double) where
  Co l <> Co r = Co $ (l + r) / 2
instance Monoid    (Co Double) where
  mempty              = white

white, black ∷ Co Double
white = co 1 1 1 1
black = co 0 0 0 1

opaque ∷ Num a ⇒ a → a → a → Co a
opaque r g b = co r g b 1

gray ∷ a → a → Co a
gray x a = co x x x a

coMult ∷ Num a ⇒ a → Co a → Co a
coMult x (Co (V4 r g b a)) = Co $ V4 (r*x) (g*x) (b*x) a


-- * Solarized
--
base03, base02, base01, base00, base0, base1, base2, base3, yellow, orange, red, magenta, violet, blue, cyan, green ∷ Co Double
base03  = co 0.000 0.169 0.212 1
base02  = co 0.027 0.212 0.259 1
base01  = co 0.345 0.431 0.459 1
base00  = co 0.396 0.482 0.514 1
base0   = co 0.514 0.580 0.588 1
base1   = co 0.576 0.631 0.631 1
base2   = co 0.933 0.910 0.835 1
base3   = co 0.992 0.965 0.890 1
yellow  = co 0.710 0.537 0.000 1
orange  = co 0.796 0.294 0.086 1
red     = co 0.863 0.196 0.184 1
magenta = co 0.827 0.212 0.510 1
violet  = co 0.423 0.443 0.769 1
blue    = co 0.149 0.545 0.824 1
cyan    = co 0.166 0.631 0.596 1
green   = co 0.522 0.600 0.000 1


-- * Axis
--
data Axis = X | Y deriving (Eq, Show)

newtype Major = Major { fromMajor ∷ Axis } deriving (Eq, Show)
newtype Minor = Minor { fromMinor ∷ Axis } deriving (Eq, Show)

other'axis ∷ Axis → Axis
other'axis X = Y
other'axis Y = X

-- * Axis-derived operations
--
class AddMax (l ∷ Type) (r ∷ Type) where
  addMax ∷ Axis → l → r → l

type Lin a = (Fractional a, Ord a, Num a)

instance Lin d ⇒ AddMax (V2 d) (V2 d) where
  addMax X  (V2 lx ly) (V2 rx ry) = V2 (lx   +   ly) (rx `max` ry)
  addMax  Y (V2 lx ly) (V2 rx ry) = V2 (lx `max` ly) (rx   +   ry)

instance Lin d ⇒ AddMax (Di d) (Di d) where
  addMax ax = Di .: on (addMax ax) _di'v

instance Lin d ⇒ AddMax (Po d) (Di d) where
  addMax ax pos by =  pos & po'd ax %~ (+ (by ^. (di'd ax)))


-- | Axis-major vector, major axis is: 1. first, 2. not recorded.
--
newtype V2A d = V2A (V2 d)

v2a ∷ Axis → d → d → V2A d
v2a X x y = V2A $ V2 x y
v2a Y x y = V2A $ V2 y x

v2a'lift ∷ Axis → V2 d → V2A d
v2a'lift X v        = V2A v
v2a'lift Y (V2 x y) = V2A $ (V2 y x)

v2'proj ∷ Axis → V2 d → d
v2'proj X (V2 x _) = x
v2'proj Y (V2 _ x) = x


-- * Orientation: _ north-west, clockwise to west.
--
data OKind  = Card | Corn
data Orient (k ∷ OKind) where
  ONW ∷ Orient Corn
  ON  ∷ Orient Card
  ONE ∷ Orient Corn
  OE  ∷ Orient Card
  OSE ∷ Orient Corn
  OS  ∷ Orient Card
  OSW ∷ Orient Corn
  OW  ∷ Orient Card
deriving instance Eq   (Orient k)
deriving instance Show (Orient k)

ori'vec ∷ Num a ⇒ Orient b → V2 a
ori'vec ON  = V2  0 (-1)
ori'vec ONE = V2  1 (-1)
ori'vec OE  = V2  1   0
ori'vec OSE = V2  1   1
ori'vec OS  = V2  0   1
ori'vec OSW = V2(-1)  1
ori'vec OW  = V2(-1)  0
ori'vec ONW = V2(-1)(-1)

-- | Given a radius 'r' and an orientation 'o', return a decomposition
--   of the corresponding vector as a pair of two-dimensional vectors.
ori'vec'pair ∷ Num a ⇒ R a → Orient b → (V2 a, V2 a)
ori'vec'pair (R r) o | ON  ← o = (z, n) | ONE ← o = (e, n)
                  | OE  ← o = (e, z) | OSE ← o = (e, s)
                  | OS  ← o = (z, s) | OSW ← o = (w, s)
                  | OW  ← o = (w, z) | ONW ← o = (w, n)
  where n = V2  0(-r)
        s = V2  0  r
        e = V2  r  0
        w = V2(-r) 0
        z = V2  0  0

-- | Given an orientation 'o', a center-point at 'c' and a radius 'r', compute a
--   clockwise chord vector, with endpoints residing on a circle of specified
--   radius, and that is orthogonal to the specified orientation.
chord'CW ∷ Num a ⇒ Orient Corn → Po a → R a → (Po a, Po a)
chord'CW o c r
  | ONE ← o = (oy, ox)
  | OSE ← o = (ox, oy)
  | OSW ← o = (oy, ox)
  | ONW ← o = (ox, oy)
  where (vx, vy) = ori'vec'pair r o
        (ox, oy) = (po'add vx c, po'add vy c)


-- * Higher-semantics geometry
--
-- | Constraint
newtype Cstr d = Cstr { _cstr'di ∷ Di d } deriving (Additive, Applicative, Functor, Eq, Semigroup, Monoid, Num, Show)
-- | Requirement
newtype Reqt d = Reqt { _reqt'di ∷ Di d } deriving (Additive, Applicative, Functor, Eq, Semigroup, Monoid, Num, Show)
-- | XXX: extraneous?
newtype Size d = Size { _size'di ∷ Di d } deriving (Additive, Applicative, Functor, Eq, Semigroup, Monoid, Num, Show)
-- | Origin
newtype Orig d = Orig { _orig'po ∷ Po d } deriving (Additive, Applicative, Functor, Eq, Semigroup, Monoid, Num, Show)
-- | Upper-left corner
newtype LU   d = LU   { _lu'po   ∷ Po d } deriving (Additive, Applicative, Functor, Eq, Semigroup, Monoid, Num, Show)
-- | Bottom-right corner
newtype RB   d = RB   { _rb'po   ∷ Po d } deriving (Additive, Applicative, Functor, Eq, Semigroup, Monoid, Num, Show)
makeLenses ''Cstr
makeLenses ''Reqt
makeLenses ''Size
makeLenses ''Orig
makeLenses ''LU
makeLenses ''RB

mkLU   ∷ d → d → LU d
mkLU   = (LU   ∘ Po) .: V2
mkRB   ∷ d → d → RB d
mkRB   = (RB   ∘ Po) .: V2
mkOrig ∷ d → d → Orig d
mkOrig = (Orig ∘ Po) .: V2
mkSize ∷ d → d → Size d
mkSize = (Size ∘ Di) .: V2

cstr'v ∷ Lens' (Cstr a) (V2 a)
cstr'v f (Cstr (Di v)) = Cstr ∘ Di <$> f v
reqt'v ∷ Lens' (Reqt a) (V2 a)
reqt'v f (Reqt (Di v)) = Reqt ∘ Di <$> f v
size'v ∷ Lens' (Size a) (V2 a)
size'v f (Size (Di v)) = Size ∘ Di <$> f v
orig'v ∷ Lens' (Orig a) (V2 a)
orig'v f (Orig (Po v)) = Orig ∘ Po <$> f v
lu'v   ∷ Lens' (LU   a) (V2 a)
lu'v   f (LU   (Po v)) = LU   ∘ Po <$> f v
rb'v   ∷ Lens' (RB   a) (V2 a)
rb'v   f (RB   (Po v)) = RB   ∘ Po <$> f v

cstr'd ∷ Axis → Lens' (Cstr a) a
cstr'd X f (Cstr (Di (V2 x y))) = Cstr ∘ Di ∘ (flip V2 y) <$> f x
cstr'd Y f (Cstr (Di (V2 x y))) = Cstr ∘ Di ∘ (id   V2 x) <$> f y
reqt'd ∷ Axis → Lens' (Reqt a) a
reqt'd X f (Reqt (Di (V2 x y))) = Reqt ∘ Di ∘ (flip V2 y) <$> f x
reqt'd Y f (Reqt (Di (V2 x y))) = Reqt ∘ Di ∘ (id   V2 x) <$> f y
size'd ∷ Axis → Lens' (Size a) a
size'd X f (Size (Di (V2 x y))) = Size ∘ Di ∘ (flip V2 y) <$> f x
size'd Y f (Size (Di (V2 x y))) = Size ∘ Di ∘ (id   V2 x) <$> f y
orig'd ∷ Axis → Lens' (Orig a) a
orig'd X f (Orig (Po (V2 x y))) = Orig ∘ Po ∘ (flip V2 y) <$> f x
orig'd Y f (Orig (Po (V2 x y))) = Orig ∘ Po ∘ (id   V2 x) <$> f y
lu'd   ∷ Axis → Lens' (LU a) a
lu'd   X f (LU   (Po (V2 x y))) = LU   ∘ Po ∘ (flip V2 y) <$> f x
lu'd   Y f (LU   (Po (V2 x y))) = LU   ∘ Po ∘ (id   V2 x) <$> f y
rb'd   ∷ Axis → Lens' (RB a) a
rb'd   X f (RB   (Po (V2 x y))) = RB   ∘ Po ∘ (flip V2 y) <$> f x
rb'd   Y f (RB   (Po (V2 x y))) = RB   ∘ Po ∘ (id   V2 x) <$> f y

instance Show d ⇒ Pretty (Cstr d) where pretty = pretty ∘ ("#<Cstr " <>) ∘ (<> ">") ∘ ppV2 ∘ (^.cstr'v)
instance Show d ⇒ Pretty (Reqt d) where pretty = pretty ∘ ("#<Reqt " <>) ∘ (<> ">") ∘ ppV2 ∘ (^.reqt'v)
instance Show d ⇒ Pretty (Size d) where pretty = pretty ∘ ("#<Size " <>) ∘ (<> ">") ∘ ppV2 ∘ (^.size'v)
instance Show d ⇒ Pretty (Orig d) where pretty = pretty ∘ ("#<Orig " <>) ∘ (<> ">") ∘ ppV2 ∘ (^.orig'v)
instance Show d ⇒ Pretty (LU   d) where pretty = pretty ∘ ("#<LU "   <>) ∘ (<> ">") ∘ ppV2 ∘ (^.lu'v)
instance Show d ⇒ Pretty (RB   d) where pretty = pretty ∘ ("#<RB "   <>) ∘ (<> ">") ∘ ppV2 ∘ (^.rb'v)

instance Lin d  ⇒ AddMax (Reqt d) (Reqt d) where
  addMax ax = Reqt .: on (addMax ax) (_reqt'di)
instance Lin d  ⇒ AddMax (Size d) (Size d) where
  addMax ax = Size .: on (addMax ax) (_size'di)

reqt'add  ∷ Lin d ⇒ Axis → Reqt d → Reqt d → Reqt d
reqt'add X  (Reqt (Di (V2 lx ly))) (Reqt (Di (V2 rx ry))) = Reqt ∘ Di $ V2 (lx   +   rx) (ly `max` ry)
reqt'add  Y (Reqt (Di (V2 lx ly))) (Reqt (Di (V2 rx ry))) = Reqt ∘ Di $ V2 (lx `max` rx) (ly   +   ry)

orig'lu ∷ Lin d ⇒ Size d → Orig d → LU d
orig'lu (Size (Di size)) = LU   ∘ (& po'v %~ (flip (-) (size / 2))) ∘ _orig'po
orig'rb ∷ Lin d ⇒ Size d → Orig d → RB d
orig'rb (Size (Di size)) = RB   ∘ (& po'v %~ (     (+) (size / 2))) ∘ _orig'po

lu'orig ∷ Lin d ⇒ Size d → LU d → Orig d
lu'orig (Size (Di size)) = Orig ∘ (& po'v %~ (     (+) (size / 2))) ∘ _lu'po
rb'orig ∷ Lin d ⇒ Size d → RB d → Orig d
rb'orig (Size (Di size)) = Orig ∘ (& po'v %~ (flip (-) (size / 2))) ∘ _rb'po

lurb'di ∷ Num d ⇒ LU d → RB d → Di d
lurb'di (LU lu) (RB rb) = poDelta rb lu


-- * TODO:
-- - alignment as parameter, instead of hard-coded N/W edge alignment
-- - switch to centre-based origin
--
orig'beside ∷ Lin d ⇒ Orient Card → Orig d → Reqt d → Reqt d → Orig d
orig'beside ON o r _t = o & orig'v._y %~ ((-)(r^.reqt'v._y))
orig'beside OS o _r t = o & orig'v._y %~ ((+)(t^.reqt'v._y))
orig'beside OW o r _t = o & orig'v._x %~ ((-)(r^.reqt'v._x))
orig'beside OE o _r t = o & orig'v._x %~ ((+)(t^.reqt'v._x))


-- * Geometry: rectangular Area
--
-- This allows different ways of specifying an area:
--  1. Po,   Di   -- bare values for center and dimension
--  2. Orig, Size -- same, but more precisely typed
--  3. LU,   Size -- origin at left upper corner
--  4. LU,   RB   -- origin at left upper corder, with size is implicit from the specified right bottom corner
--
type AreaDict d = (Eq d, Lin d, Pretty d, Show d)

data Area' (a ∷ Type → Type) (b ∷ Type → Type) d where
  Area ∷ AreaDict d ⇒
    { _area'a ∷ a d
    , _area'b ∷ b d
    } → Area' a b d
makeLenses ''Area'

deriving instance (Eq   (a d), Eq   (b d)) ⇒ Eq   (Area' a b d)
deriving instance (Show (a d), Show (b d)) ⇒ Show (Area' a b d)

class    (Additive a, Additive b, Fractional d, Ord d, Pretty d, Show d) ⇒ NoArea a b d where
  noArea ∷ Area' a b d
instance (Additive a, Additive b, Fractional d, Ord d, Pretty d, Show d) ⇒ NoArea a b d where
  noArea = Area zero zero

pretty'Area'Int ∷ RealFrac d ⇒ FromArea a b LU Size d ⇒ Area' a b d → Doc ann
pretty'Area'Int a =
  let Area (LU (Po (V2 x y))) (Size (Di d)) = from'area a
  in (pretty ∘ ppV2 $ floor <$> d)
     <> pretty '+' <> pretty (floor x ∷ Int) <> pretty '+' <> pretty (floor y ∷ Int)

-- XXX: this is a lazy, slow implementation, that suffers from conversion roundtrips
area'split'start ∷ RealFrac d ⇒ FromArea a b LU Size d ⇒ FromArea LU Size a b d ⇒ Axis → d → Area' a b d → (Area' a b d, Area' a b d)
area'split'start axis spli a =
  let Area (LU p) (Size d) = from'area a
  in ( from'area $ Area (LU $ p)                         (Size $ d & di'd axis .~           spli)
     , from'area $ Area (LU $ p & po'd axis %~ (+ spli)) (Size $ d & di'd axis %~ (flip (-) spli)))
area'split'end   ∷ RealFrac d ⇒ FromArea a b LU Size d ⇒ FromArea LU Size a b d ⇒ Axis → d → Area' a b d → (Area' a b d, Area' a b d)
area'split'end   axis spli a =
  let Area (LU _p) (Size d) = from'area a
      axis'dim              = d^.di'd axis
  in area'split'start axis (axis'dim - spli) a

instance (FromArea a b LU Size d, RealFrac d) ⇒ Pretty (Area' a b d) where
  pretty x = pretty '#' <> angles ("Area" <+> pretty'Area'Int x)

type Area      d = Area' Po   Di   d
type Area'Orig d = Area' Orig Size d
type Area'LU   d = Area' LU   Size d
type Area'LURB d = Area' LU   RB   d

class    AreaDict d ⇒ FromArea fa   fb   ta   tb   d where
  from'area ∷ Area' fa fb d → Area' ta tb d

instance AreaDict d ⇒ FromArea a    b    a    b    d where from'area = id
instance AreaDict d ⇒ FromArea Po   Di   Orig Size d where from'area (Area       p        d ) = Area (Orig p)                      (Size d)
instance AreaDict d ⇒ FromArea Orig Size Po   Di   d where from'area (Area (Orig p) (Size d)) = Area       p                             d

instance AreaDict d ⇒ FromArea Orig Size LU   Size d where from'area (Area (Orig p) (Size d)) = Area (LU $ po'sub (_di'v d / 2) p) (Size d)
instance AreaDict d ⇒ FromArea LU   Size Po   Di   d where from'area (Area (LU   p) (Size d)) = Area (     po'add (_di'v d / 2) p)       d
instance AreaDict d ⇒ FromArea LU   Size LU   RB   d where from'area (Area (LU   p) (Size d)) = Area (LU $ p)                      (RB $ po'add (_di'v d) p)
--   from'area (Area (Size d) (Orig p)) = Area (Size d) (LU   p)
--   from'area (Area       d        p)  = Area (Size d) (LU   p)
--   from'area (Area (Size d) (Orig p)) = Area (Size d) (LU   p)
--   from'area (Area (Size d) (LU   p)) = Area (Size d) (Orig p)

class AreaDict d ⇒ HasArea a d where
  area'PoDi ∷ AreaDict d ⇒ a d → Area      d
  area'LU   ∷ AreaDict d ⇒ a d → Area'LU   d
  area'LURB ∷ AreaDict d ⇒ a d → Area'LURB d
  area'Orig ∷ AreaDict d ⇒ a d → Area'Orig d
  luOf      ∷ AreaDict d ⇒ a d → LU d
  dimOf     ∷ AreaDict d ⇒ a d → Di d
  {-# MINIMAL area'PoDi | area'LU | area'Orig | area'LURB #-}
  area'Orig = from'area ∘ area'PoDi
  area'LU   = from'area ∘ area'Orig
  area'LURB = from'area ∘ area'LU
  area'PoDi = from'area ∘ area'LU
  luOf      = _area'a   ∘ area'LU
  dimOf x   = lurb'di (ar^.area'a) (ar^.area'b)
    where ar = area'LURB x

type AreaTuple d = (Di d, Po d)

instance AreaDict d ⇒ HasArea (Area' Po   Di  ) d where area'PoDi = id
instance AreaDict d ⇒ HasArea (Area' Orig Size) d where area'Orig = id
instance AreaDict d ⇒ HasArea (Area' LU   Size) d where area'LU   = id
instance AreaDict d ⇒ HasArea (Area' LU   RB  ) d where area'LURB = id

instance (AreaDict d, Monoid (po d), Monoid (di d)) ⇒ Semigroup (Area' po di d) where
  Area lpo ldi <> Area rpo' rdi = Area (lpo <> rpo') (ldi <> rdi)
instance (AreaDict d, Monoid (po d), Monoid (di d)) ⇒ Monoid    (Area' po di d) where
  mempty = Area mempty mempty
