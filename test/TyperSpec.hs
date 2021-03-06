{-# LANGUAGE OverloadedStrings #-}

module TyperSpec (spec, typeString) where

import           Data.Default
import qualified Nix.Expr as NAst
import qualified Nix.Parser as NParser
import qualified NixLight.Ast as Ast
import qualified NixLight.FromHNix
import           Test.Hspec
import qualified Typer.Error
import qualified Typer.Infer as Infer
import qualified Types
import qualified Types.Arrow as Arrow
import qualified Types.Node as Node
import           Types.SetTheoretic
import qualified Types.Singletons as Singleton

import           Data.Function ((&))

import qualified Control.Monad.Writer as W

shouldSuccessAs :: (Eq a, Show a)
                => W.Writer [Typer.Error.T] a
                -> a
                -> Expectation
shouldSuccessAs res y =
  case W.runWriter res of
    (x, []) -> x `shouldBe` y
    (_, errs) -> expectationFailure (show errs)

isInferredAs :: String -> Types.T -> Expectation
isInferredAs prog typ =
  let ast = parseString prog in
  (Infer.inferExpr def =<< ast) `shouldSuccessAs` Node.noId typ

checksAgain :: String -> Types.T -> Expectation
checksAgain prog typ =
  let ast = parseString prog in
  (Infer.checkExpr def (Node.noId typ) =<< ast) `shouldSuccessAs` ()

inferredAndChecks :: String -> Types.T -> Expectation
inferredAndChecks prog typ = do
  isInferredAs prog typ
  checksAgain prog typ

shouldFail :: Show a
           => W.Writer [Typer.Error.T] a
           -> b
           -> Expectation
shouldFail res _y =
  case W.runWriter res of
    (x, []) -> expectationFailure
                 $ "Expected an error, but got type " ++ show x
    (_, _) -> pure ()

typeString :: String -> W.Writer [Typer.Error.T] Types.Node
typeString s = Infer.inferExpr def =<< parseString s

checkString :: String -> Types.Node -> W.Writer [Typer.Error.T] ()
checkString s typ = Infer.checkExpr def typ =<< parseString s

parseString :: String -> W.Writer [Typer.Error.T] Ast.ExprLoc
parseString s = do
  hnixAst <- NixLight.FromHNix.trifectaToWarnings
    (NAst.annToAnnF $ NAst.Ann (NAst.SrcSpan mempty mempty) $ NAst.NSym "undefined")
    $ NParser.parseNixStringLoc s
  NixLight.FromHNix.closedExpr hnixAst

spec :: Spec
spec = do
  describe "Inference and check tests" $ do
    it "Integer constant" $
      "1" `inferredAndChecks` Singleton.int 1
    it "Annotated constant" $
      "2 /*: Int */" `inferredAndChecks` Types.int full
    it "Singleton int annot" $
      "2 /*: 2 */" `inferredAndChecks` Singleton.int 2
    it "Singleton bool annot" $
      "true /*: true */" `inferredAndChecks` Singleton.bool True
    it "True constant" $
      "true" `inferredAndChecks` Singleton.bool True
    it "False constant" $
      "false" `inferredAndChecks` Singleton.bool False
    describe "Lambdas" $ do
      it "trivial" $
        "x: 1" `inferredAndChecks`
          Types.arrow (Arrow.atom full (Node.noId $ Singleton.int 1))
      it "trivial annotated" $
        "x /*: Int */: 1" `inferredAndChecks`
          Types.arrow (Arrow.atom (Node.noId $ Types.int full) (Node.noId $ Singleton.int 1))
      it "simple annotated" $
        "x /*: Int */: x" `inferredAndChecks`
          Types.arrow (Arrow.atom (Node.noId $ Types.int full) (Node.noId $ Types.int full))
      it "higher order" $
        let intarrint =
              Node.noId $
              Types.arrow (Arrow.atom (Node.noId $ Types.int full) (Node.noId $ Types.int full))
        in
        "(x /*: Int -> Int */: x)" `inferredAndChecks`
          Types.arrow (Arrow.atom intarrint intarrint)
    describe "Application" $ do
      it "trivial" $
        "(x: 1) 2" `inferredAndChecks` Singleton.int 1
      it "simple" $
        "(x /*: Int */: x) 2" `inferredAndChecks` Types.int full
      it "higher order" $
        "(x /*: Int -> Int */: x 1) (x /*: Int */: x)"
          `inferredAndChecks` Types.int full
      it "intersection1" $
        "let f /*: (Int -> Int) & (Bool -> Bool) */ = x: x; in f 1"
        `inferredAndChecks`
        Types.int full
      it "intersection2" $
        "let f /*: (Int -> Int) & (Bool -> Bool) */ = x: x; in f true"
        `inferredAndChecks`
        Types.bool full
    describe "let-bindings" $ do
      it "trivial" $
        "let x = 1; in x" `inferredAndChecks` Singleton.int 1
      it "trivial annotated" $
        "let x /*: Int */ = 1; in x" `inferredAndChecks` Types.int full
      it "multiple" $
        "let x = 1; y = x; in y" `inferredAndChecks` full
      it "multiple annotated" $
        "let x /*: Int */ = 1; y = x; in y" `inferredAndChecks` Types.int full
    describe "If-then-else" $ do
      it "Always true" $
        "if true then 1 else 2" `inferredAndChecks` Singleton.int 1
      it "Always false" $
        "if false then 1 else 2" `inferredAndChecks` Singleton.int 2
      it "Undecided" $
        "let x /*: Bool */ = true; in if x then 1 else 3"
          `inferredAndChecks` (Singleton.int 1 \/ Singleton.int 3)
    describe "wrong" $ do
      it "inference" $ typeString "(x /*: Empty */: x) 1" & shouldFail
      it "checking" $
        checkString "(x /*: Empty */: x) 1" (Node.noId $ Types.int full)
          & shouldFail
    it "undef type" $
      "undefined" `inferredAndChecks` empty
    it "type-annot" $
      "1 /*: Int */" `inferredAndChecks` Types.int full
    describe "recursive types" $ do
      it "simple" $
        "1 /*: X where X = Y and Y = Int */" `isInferredAs` Types.int full
      it "really recursive" $
        "(1 /*: X where X = Int | X -> Int */) /*: Any */" `isInferredAs` full

  describe "Check only" $
    describe "Application" $
      it "identity" $
        "(x: x) 1" `checksAgain` Types.int full
