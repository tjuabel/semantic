module Source.Spec where

import Prologue
import Range
import Source
import SourceSpan
import Test.Hspec
import Test.Hspec.QuickCheck

spec :: Spec
spec = parallel $ do
  describe "actualLineRanges" $ do
    prop "produces 1 more range than there are newlines" $
      \ s -> length (actualLineRanges (totalRange s) (fromList s)) `shouldBe` succ (length (filter (== '\n') s))

    prop "produces exhaustive ranges" $
      \ s -> let source = fromList s in
        foldMap (`slice` source) (actualLineRanges (totalRange s) source) `shouldBe` source

  describe "sourceSpanToRange" $ do
    prop "computes the range covering a span in some source" $
      \ s -> let source = fromList s
                 spans = zipWith (\ i Range {..} -> SourceSpan "" (SourcePos i 0) (SourcePos i (end - start))) [0..] ranges
                 ranges = actualLineRanges (totalRange source) source in
      sourceSpanToRange source <$> spans `shouldBe` ranges
