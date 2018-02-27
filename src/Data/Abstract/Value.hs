{-# LANGUAGE ConstraintKinds, DataKinds, FunctionalDependencies, FlexibleContexts, FlexibleInstances, MultiParamTypeClasses, ScopedTypeVariables, TypeFamilies, TypeOperators #-}
module Data.Abstract.Value where

import Data.Abstract.Address
import Data.Abstract.Environment
import Data.Abstract.Store
import Data.Abstract.FreeVariables
import Data.Abstract.Live
import qualified Data.Abstract.Type as Type
import Data.ByteString (ByteString)
import Data.Functor.Classes.Generic
import Data.Semigroup
import qualified Data.Set as Set
import Data.Union
import GHC.Generics
import Prelude hiding (Integer, String)
import qualified Prelude

type ValueConstructors location
  = '[Closure location
    , Interface location
    , Unit
    , Boolean
    , Integer
    , String
    ]

-- | Open union of primitive values that terms can be evaluated to.
type Value location = Union (ValueConstructors location)

-- TODO: Parameterize Value by the set of constructors s.t. each language can have a distinct value union.
-- TODO: Wrap the Value union in a newtype to differentiate from (eventual) à la carte Types.

-- | A function value consisting of a list of parameters, the body of the function, and an environment of bindings captured by the body.
data Closure location term = Closure [Name] term (Environment location (Value location term))
  deriving (Eq, Generic1, Ord, Show)

instance (Eq location) => Eq1 (Closure location) where liftEq = genericLiftEq
instance (Ord location) => Ord1 (Closure location) where liftCompare = genericLiftCompare
instance (Show location) => Show1 (Closure location) where liftShowsPrec = genericLiftShowsPrec

-- | A program value consisting of the value of the program and it's enviornment of bindings.
data Interface location term = Interface (Value location term) (Environment location (Value location term))
  deriving (Eq, Generic1, Ord, Show)

instance (Eq location) => Eq1 (Interface location) where liftEq = genericLiftEq
instance (Ord location) => Ord1 (Interface location) where liftCompare = genericLiftCompare
instance (Show location) => Show1 (Interface location) where liftShowsPrec = genericLiftShowsPrec

-- | The unit value. Typically used to represent the result of imperative statements.
data Unit term = Unit
  deriving (Eq, Generic1, Ord, Show)

instance Eq1 Unit where liftEq = genericLiftEq
instance Ord1 Unit where liftCompare = genericLiftCompare
instance Show1 Unit where liftShowsPrec = genericLiftShowsPrec

-- | Boolean values.
newtype Boolean term = Boolean Prelude.Bool
  deriving (Eq, Generic1, Ord, Show)

instance Eq1 Boolean where liftEq = genericLiftEq
instance Ord1 Boolean where liftCompare = genericLiftCompare
instance Show1 Boolean where liftShowsPrec = genericLiftShowsPrec

-- | Arbitrary-width integral values.
newtype Integer term = Integer Prelude.Integer
  deriving (Eq, Generic1, Ord, Show)

instance Eq1 Integer where liftEq = genericLiftEq
instance Ord1 Integer where liftCompare = genericLiftCompare
instance Show1 Integer where liftShowsPrec = genericLiftShowsPrec

-- | String values.
newtype String term = String ByteString
  deriving (Eq, Generic1, Ord, Show)

instance Eq1 String where liftEq = genericLiftEq
instance Ord1 String where liftCompare = genericLiftCompare
instance Show1 String where liftShowsPrec = genericLiftShowsPrec

-- | The environment for an abstract value type.
type EnvironmentFor v = Environment (LocationFor v) v

-- | The store for an abstract value type.
type StoreFor v = Store (LocationFor v) v

-- | The location type (the body of 'Address'es) which should be used for an abstract value type.
type family LocationFor value :: * where
  LocationFor (Value location term) = location
  LocationFor (Type.Type term) = Monovariant


-- | Value types, e.g. closures, which can root a set of addresses.
class ValueRoots l v | v -> l where
  -- | Compute the set of addresses rooted by a given value.
  valueRoots :: v -> Live l v

-- | An interface for constructing abstract values.
class AbstractValue t v | v -> t where
  -- | Construct an abstract unit value.
  unit :: v

  -- | Construct an abstract integral value.
  integer :: Prelude.Integer -> v

  -- | Construct an abstract boolean value.
  boolean :: Bool -> v

  -- | Construct an abstract string value.
  string :: ByteString -> v

  -- abstract :: Monad m => [Name] -> (t, m v) -> m v


-- Instances

instance (FreeVariables term, Ord location) => ValueRoots location (Value location term) where
  valueRoots v
    | Just (Closure names body env) <- prj v = envRoots env (foldr Set.delete (freeVariables body) names)
    | Just (Interface _ env) <- prj v        = envAll env
    | otherwise                              = mempty

-- | Construct a 'Value' wrapping the value arguments (if any).
instance AbstractValue term (Value location term) where
  unit = inj Unit
  integer = inj . Integer
  boolean = inj . Boolean
  string = inj . String
  -- abstract names (term, _) = inj . Closure names term <$> ask

instance ValueRoots Monovariant (Type.Type term) where
  valueRoots _ = mempty

-- | Discard the value arguments (if any), constructing a 'Type.Type' instead.
instance AbstractValue term (Type.Type term) where
  unit = Type.Unit
  integer _ = Type.Int
  boolean _ = Type.Bool
  string _ = Type.String
