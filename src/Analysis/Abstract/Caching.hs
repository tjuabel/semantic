{-# LANGUAGE DataKinds, GeneralizedNewtypeDeriving, MultiParamTypeClasses, ScopedTypeVariables, StandaloneDeriving, TypeApplications, TypeFamilies, TypeOperators, UndecidableInstances #-}
module Analysis.Abstract.Caching
  ( evaluateCache )
  where

import Prologue
import Data.Monoid (Alt(..))
import Control.Abstract.Evaluator
import Control.Monad.Effect.Fresh
import Control.Monad.Effect.NonDet
import Data.Abstract.Address
import Data.Abstract.Cache
import Data.Abstract.Configuration
import Data.Abstract.Evaluatable
import Data.Abstract.Store
import Data.Abstract.Value

-- | The effects necessary for caching analyses.
type CachingEffects term value
  =  Fresh                        -- For 'MonadFresh'. TODO: Extract typing constraints into a separate analysis.
  ': NonDetEff                    -- For 'Alternative' & 'MonadNonDet'.
  ': Reader (CacheFor term value) -- For the in-cache.
  ': State (CacheFor term value)  -- For the out-cache
  ': EvaluatorEffects term value

-- | The cache for term and abstract value types.
type CacheFor term value = Cache (LocationFor value) term value

newtype CachingAnalysis term value a = CachingAnalysis { runCachingAnalysis :: Evaluator term value (CachingEffects term value) a }
  deriving (Alternative, Applicative, Functor, Monad, MonadFail, MonadFresh, MonadNonDet)

deriving instance Ord (LocationFor value) => MonadEvaluator (CachingAnalysis term value)

-- TODO: reabstract these later on

askCache :: CachingAnalysis term value (CacheFor term value)
askCache = CachingAnalysis (Evaluator ask)

localCache :: (CacheFor term value -> CacheFor term value) -> CachingAnalysis term value a -> CachingAnalysis term value a
localCache f (CachingAnalysis (Evaluator a)) = CachingAnalysis (Evaluator (local f a))

asksCache :: (CacheFor term value -> a) -> CachingAnalysis term value a
asksCache f = f <$> askCache

getsCache :: (CacheFor term value -> a) -> CachingAnalysis term value a
getsCache f = f <$> getCache

getCache :: CachingAnalysis term value (CacheFor term value)
getCache = CachingAnalysis (Evaluator get)

putCache :: CacheFor term value -> CachingAnalysis term value ()
putCache cache = CachingAnalysis (Evaluator (put cache))

modifyCache :: (CacheFor term value -> CacheFor term value) -> CachingAnalysis term value ()
modifyCache f = fmap f getCache >>= putCache

-- | This instance coinductively iterates the analysis of a term until the results converge.
instance ( Corecursive term
         , Ord term
         , Ord value
         , Ord (CellFor value)
         , Evaluatable (Base term)
         , Foldable (Cell (LocationFor value))
         , FreeVariables term
         , MonadAddressable (LocationFor value) (CachingAnalysis term value)
         , MonadValue value (CachingAnalysis term value)
         , Recursive term
         , Semigroup (CellFor value)
         )
         => MonadAnalysis (CachingAnalysis term value) where
  analyzeTerm e = do
    c <- getConfiguration (embedSubterm e)
    -- Convergence here is predicated upon an Eq instance, not α-equivalence
    cache <- converge (\ prevCache -> do
      putCache (mempty :: CacheFor term value)
      putStore (configurationStore c)
      -- We need to reset fresh generation so that this invocation converges.
      reset 0
      -- This is subtle: though the calling context supports nondeterminism, we want
      -- to corral all the nondeterminism that happens in this @eval@ invocation, so
      -- that it doesn't "leak" to the calling context and diverge (otherwise this
      -- would never complete). We don’t need to use the values, so we 'gather' the
      -- nondeterministic values into @()@.
      _ <- localCache (const prevCache) (gather (memoizeEval e) :: CachingAnalysis term value ())
      getCache) mempty
    maybe empty scatter (cacheLookup c cache)


-- | Coinductively-cached evaluation.
evaluateCache :: forall value term
              . ( Ord value
                , Ord term
                , Ord (LocationFor value)
                , Ord (CellFor value)
                , Corecursive term
                , Evaluatable (Base term)
                , FreeVariables term
                , Foldable (Cell (LocationFor value))
                , Functor (Base term)
                , Recursive term
                , MonadAddressable (LocationFor value) (CachingAnalysis term value)
                , MonadValue value (CachingAnalysis term value)
                , Semigroup (CellFor value)
                , ValueRoots (LocationFor value) value
                )
              => term
              -> Final (CachingEffects term value) value
evaluateCache = run @(CachingEffects term value) . runEvaluator . runCachingAnalysis . evaluateTerm

-- | Iterate a monadic action starting from some initial seed until the results converge.
--
--   This applies the Kleene fixed-point theorem to finitize a monotone action. cf https://en.wikipedia.org/wiki/Kleene_fixed-point_theorem
converge :: (Eq a, Monad m)
         => (a -> m a) -- ^ A monadic action to perform at each iteration, starting from the result of the previous iteration or from the seed value for the first iteration.
         -> a          -- ^ An initial seed value to iterate from.
         -> m a        -- ^ A computation producing the least fixed point (the first value at which the actions converge).
converge f = loop
  where loop x = do
          x' <- f x
          if x' == x then
            pure x
          else
            loop x'

-- | Nondeterministically write each of a collection of stores & return their associated results.
scatter :: (Alternative m, Foldable t, MonadEvaluator m) => t (a, Store (LocationFor (ValueFor m)) (ValueFor m)) -> m a
scatter = getAlt . foldMap (\ (value, store') -> Alt (putStore store' *> pure value))

-- | Evaluation of a single iteration of an analysis, given an in-cache as an oracle for results and an out-cache to record computed results in.
memoizeEval :: forall value term
            . ( Ord value
              , Ord term
              , Ord (LocationFor value)
              , Ord (CellFor value)
              , Corecursive term
              , Evaluatable (Base term)
              , FreeVariables term
              , Foldable (Cell (LocationFor value))
              , Functor (Base term)
              , Recursive term
              , MonadAddressable (LocationFor value) (CachingAnalysis term value)
              , MonadValue value (CachingAnalysis term value)
              , Semigroup (CellFor value)
              )
            => SubtermAlgebra (Base term) term (CachingAnalysis term value value)
memoizeEval e = do
  c <- getConfiguration (embedSubterm e)
  cached <- getsCache (cacheLookup c)
  case cached of
    Just pairs -> scatter pairs
    Nothing -> do
      pairs <- asksCache (fromMaybe mempty . cacheLookup c)
      modifyCache (cacheSet c pairs)
      v <- eval e
      store' <- getStore
      modifyCache (cacheInsert c (v, store'))
      pure v
