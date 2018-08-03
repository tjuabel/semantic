{-# LANGUAGE OverloadedLists, TypeOperators #-}

module Reprinting.Spec where

import SpecHelpers hiding (project, inject)

import Data.Functor.Foldable (embed, cata)
import qualified Data.Language as Language
import qualified Data.Syntax.Literal as Literal
import Data.Algebra
import Reprinting.Algebraic
import Reprinting.Pipeline
import Data.Sum
import Semantic.IO
import Data.Blob

spec :: Spec
spec = describe "reprinting" $ do
  let path = "test/fixtures/javascript/reprinting/map.json"

  (src, tree) <- runIO $ do
    src  <- blobSource <$> readBlobFromPath (File path Language.JSON)
    tree <- parseFile jsonParser "test/fixtures/javascript/reprinting/map.json"
    pure (src, tree)

  describe "tokenization" $ do

    it "should pass over a pristine tree" $ do
      let tagged = mark Pristine tree
      let toks = reprint src tagged
      toks `shouldBe` [Chunk src]

    it "should emit control tokens but only 1 chunk for a wholly-modified tree" $ do
      let toks = reprint src (mark Modified tree)
      forM_ @[] [List, Associative] $ \t -> do
        toks `shouldSatisfy` (elem (TControl (Enter t)))
        toks `shouldSatisfy` (elem (TControl (Exit t)))

  describe "pipeline" $ do
    it "should roundtrip exactly over a pristine tree" $ do
      let tagged = mark Pristine tree
      let printed = runReprinter (Proxy @'Language.JSON) src tagged
      printed `shouldBe` Right src

    it "should roundtrip exactly over a wholly-modified tree" $ do
      let tagged = mark Modified tree
      let printed = runReprinter (Proxy @'Language.JSON) src tagged
      printed `shouldBe` Right src

    it "should be able to parse the output of a refactor" $ do
      let tagged = increaseNumbers (mark Modified tree)
      let (Right printed) = runReprinter (Proxy @'Language.JSON) src tagged
      tree' <- runTask (parse jsonParser (Blob printed path Language.JSON))
      length tree `shouldSatisfy` (/= 0)
