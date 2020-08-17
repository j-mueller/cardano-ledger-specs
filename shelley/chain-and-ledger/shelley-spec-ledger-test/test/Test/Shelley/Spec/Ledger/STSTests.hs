{-# LANGUAGE DataKinds #-}
{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE TypeApplications #-}

module Test.Shelley.Spec.Ledger.STSTests
  ( multisigExamples,
    chainExamples,
  )
where

import Control.State.Transition.Extended (TRC (..))
import Data.Either (fromRight, isRight)
import qualified Data.Map.Strict as Map
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map (empty)
import Data.Proxy
import qualified Data.Set as Set
import Shelley.Spec.Ledger.API
  ( DPState (..),
    EpochState (..),
    LedgerState (..),
    NewEpochState (..),
    PState (..),
    TICK,
    TickEnv,
  )
import Shelley.Spec.Ledger.BaseTypes (Network (..))
import Shelley.Spec.Ledger.Coin (Coin)
import Shelley.Spec.Ledger.Credential (pattern ScriptHashObj)
import Shelley.Spec.Ledger.Keys
  ( KeyHash,
    KeyRole (..),
    asWitness,
    hashKey,
    vKey,
  )
import Shelley.Spec.Ledger.LedgerState
  ( WitHashes (..),
    getGKeys,
  )
import Shelley.Spec.Ledger.STS.Chain (totalAda)
import Shelley.Spec.Ledger.STS.Tick (pattern TickEnv)
import Shelley.Spec.Ledger.STS.Utxow (PredicateFailure (..))
import Shelley.Spec.Ledger.Slot (SlotNo (..))
import Shelley.Spec.Ledger.Tx (hashScript)
import Shelley.Spec.Ledger.TxData (Wdrl (..), pattern RewardAcnt)
import Shelley.Spec.Ledger.TxData
  ( PoolParams,
  )
import Test.Shelley.Spec.Ledger.ConcreteCryptoTypes (C)
import Test.Shelley.Spec.Ledger.Examples
  ( ex4A,
    ex4B,
    ex5AReserves,
    ex5ATreasury,
    ex5BReserves,
    ex5BTreasury,
    ex5CReserves,
    ex5CTreasury,
    ex5DReserves',
    ex5DTreasury',
    ex6A,
    ex6A',
    ex6BExpectedNES,
    ex6BExpectedNES',
    ex6BPoolParams,
    test5DReserves,
    test5DTreasury,
    testCHAINExample,
  )
import qualified Test.Shelley.Spec.Ledger.Examples.Cast as Cast
import Test.Shelley.Spec.Ledger.Examples.EmptyBlock (exEmptyBlock)
import Test.Shelley.Spec.Ledger.Examples.PoolLifetime (poolLifetimeExample)
import Test.Shelley.Spec.Ledger.Examples.Updates (updatesExample)
import Test.Shelley.Spec.Ledger.MultiSigExamples
  ( aliceAndBob,
    aliceAndBobOrCarl,
    aliceAndBobOrCarlAndDaria,
    aliceAndBobOrCarlOrDaria,
    aliceOnly,
    aliceOrBob,
    applyTxWithScript,
    bobOnly,
  )
import Test.Shelley.Spec.Ledger.Utils
  ( applySTSTest,
    maxLLSupply,
    runShelleyBase,
  )
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit ((@?=), Assertion, assertBool, assertFailure, testCase)

-- | Applies the TICK transition to a given chain state,
-- and check that some component of the result is as expected.
testTICKChainState ::
  (Show a, Eq a) =>
  NewEpochState C Coin ->
  TickEnv C ->
  SlotNo ->
  (NewEpochState C Coin -> a) ->
  a ->
  Assertion
testTICKChainState initSt env slot focus expectedSt = do
  let result = runShelleyBase $ applySTSTest @(TICK C Coin) (TRC (env, initSt, slot))
  case result of
    Right res -> focus res @?= expectedSt
    Left err -> assertFailure $ show err

newEpochToPoolParams ::
  NewEpochState C Coin ->
  (Map (KeyHash 'StakePool C) (PoolParams C))
newEpochToPoolParams = _pParams . _pstate . _delegationState . esLState . nesEs

newEpochToFuturePoolParams ::
  NewEpochState C Coin ->
  (Map (KeyHash 'StakePool C) (PoolParams C))
newEpochToFuturePoolParams = _fPParams . _pstate . _delegationState . esLState . nesEs

testAdoptEarlyPoolRegistration :: Assertion
testAdoptEarlyPoolRegistration =
  testTICKChainState
    ex6BExpectedNES'
    (TickEnv $ getGKeys (ex6BExpectedNES' @C @Coin))
    (SlotNo 110)
    (\n -> (newEpochToPoolParams n, newEpochToFuturePoolParams n))
    (ex6BPoolParams, Map.empty)

testAdoptLatePoolRegistration :: Assertion
testAdoptLatePoolRegistration =
  testTICKChainState
    ex6BExpectedNES
    (TickEnv $ getGKeys (ex6BExpectedNES @C @Coin))
    (SlotNo 110)
    (\n -> (newEpochToPoolParams n, newEpochToFuturePoolParams n))
    (ex6BPoolParams, Map.empty)

genesisDelegExample :: TestTree
genesisDelegExample =
  testGroup
    "genesis delegation"
    [ testCase "stage genesis key delegation" $ testCHAINExample @C @Coin (ex4A p),
      testCase "adopt genesis key delegation" $ testCHAINExample @C @Coin (ex4B p)
    ]
  where
    p :: Proxy C
    p = Proxy

mirExample :: TestTree
mirExample =
  testGroup
    "move inst rewards"
    [ testCase "create MIR cert - reserves" $ testCHAINExample @C @Coin (ex5AReserves p),
      testCase "create MIR cert - treasury" $ testCHAINExample @C @Coin (ex5ATreasury p),
      testCase "FAIL: insufficient core node signatures MIR reserves" $
        testCHAINExample @C @Coin (ex5BReserves p),
      testCase "FAIL: insufficient core node signatures MIR treasury" $
        testCHAINExample @C @Coin (ex5BTreasury p),
      testCase "FAIL: MIR insufficient reserves" $
        testCHAINExample @C @Coin (ex5CReserves p),
      testCase "FAIL: MIR insufficient treasury" $
        testCHAINExample @C @Coin (ex5CTreasury p),
      testCase "apply reserves MIR at epoch boundary" (test5DReserves (Proxy::Proxy(C,Coin))),
      testCase "apply treasury MIR at epoch boundary" (test5DTreasury (Proxy::Proxy(C,Coin)))
    ]
  where
    p :: Proxy C
    p = Proxy

latePoolRegExample :: TestTree
latePoolRegExample =
  testGroup
    "late pool registration"
    [ testCase "Early Pool Re-registration" $ testCHAINExample @C @Coin (ex6A p),
      testCase "Late Pool Re-registration" $ testCHAINExample @C @Coin (ex6A' p),
      testCase "Adopt Early Pool Re-registration" $ testAdoptEarlyPoolRegistration,
      testCase "Adopt Late Pool Re-registration" $ testAdoptLatePoolRegistration
    ]
  where
    p :: Proxy C
    p = Proxy

miscPresOfAdaInExamples :: TestTree
miscPresOfAdaInExamples =
  testGroup
    "misc preservation of ADA"
    [ testCase "CHAIN example 5D Reserves" $
        (totalAda @C @Coin (fromRight (error "CHAIN example 5D") (ex5DReserves' p)) @?= maxLLSupply),
      testCase "CHAIN example 5D Treasury" $
        (totalAda @C @Coin (fromRight (error "CHAIN example 5D") (ex5DTreasury' p)) @?= maxLLSupply)
    ]
  where
    p :: Proxy C
    p = Proxy

chainExamples :: TestTree
chainExamples =
  testGroup
    "CHAIN examples"
    [ testCase "empty block" $ testCHAINExample @C @Coin exEmptyBlock,
      poolLifetimeExample,
      updatesExample,
      genesisDelegExample,
      mirExample,
      latePoolRegExample,
      miscPresOfAdaInExamples
    ]

multisigExamples :: TestTree
multisigExamples =
  testGroup
    "MultiSig Examples"
    [ testCase "Alice uses SingleSig script" testAliceSignsAlone,
      testCase "FAIL: Alice doesn't sign in multi-sig" testAliceDoesntSign,
      testCase "Everybody signs in multi-sig" testEverybodySigns,
      testCase "FAIL: Wrong script for correct signatures" testWrongScript,
      testCase "Alice || Bob, Alice signs" testAliceOrBob,
      testCase "Alice || Bob, Bob signs" testAliceOrBob',
      testCase "Alice && Bob, both sign" testAliceAndBob,
      testCase "FAIL: Alice && Bob, Alice signs" testAliceAndBob',
      testCase "FAIL: Alice && Bob, Bob signs" testAliceAndBob'',
      testCase "Alice && Bob || Carl, Alice && Bob sign" testAliceAndBobOrCarl,
      testCase "Alice && Bob || Carl, Carl signs" testAliceAndBobOrCarl',
      testCase "Alice && Bob || Carl && Daria, Alice && Bob sign" testAliceAndBobOrCarlAndDaria,
      testCase "Alice && Bob || Carl && Daria, Carl && Daria sign" testAliceAndBobOrCarlAndDaria',
      testCase "Alice && Bob || Carl || Daria, Alice && Bob sign" testAliceAndBobOrCarlOrDaria,
      testCase "Alice && Bob || Carl || Daria, Carl signs" testAliceAndBobOrCarlOrDaria',
      testCase "Alice && Bob || Carl || Daria, Daria signs" testAliceAndBobOrCarlOrDaria'',
      testCase "two scripts: Alice Or Bob / alice And Bob Or Carl" testTwoScripts,
      testCase "FAIL: two scripts: Alice Or Bob / alice And Bob Or Carl" testTwoScripts',
      testCase "script and Key: Alice And Bob and alicePay" testScriptAndSKey,
      testCase "FAIL: script and Key: Alice And Bob and alicePay" testScriptAndSKey',
      testCase "script and Key: Alice Or Bob and alicePay, only Alice" testScriptAndSKey'',
      testCase "script and Key: Alice And Bob Or Carl and alicePay, Alice and Carl sign" testScriptAndSKey''',
      testCase "withdraw from script locked account, same script" testRwdAliceSignsAlone,
      testCase "FAIL: withdraw from script locked account" testRwdAliceSignsAlone',
      testCase "withdraw from script locked account, different script" testRwdAliceSignsAlone'',
      testCase "FAIL: withdraw from script locked account, signed, missing script" testRwdAliceSignsAlone'''
    ]

testAliceSignsAlone :: Assertion
testAliceSignsAlone =
  assertBool s (isRight utxoSt')
  where
    p :: Proxy C
    p = Proxy
    utxoSt' =
      applyTxWithScript p [(aliceOnly p, 11000)] [aliceOnly p] (Wdrl Map.empty) 0 [asWitness Cast.alicePay]
    s = "problem: " ++ show utxoSt'

testAliceDoesntSign :: Assertion
testAliceDoesntSign =
  utxoSt' @?= Left [[ScriptWitnessNotValidatingUTXOW (Set.singleton $ hashScript (aliceOnly p))]]
  where
    p :: Proxy C
    p = Proxy
    utxoSt' =
      applyTxWithScript
        p
        [(aliceOnly p, 11000)]
        [aliceOnly p]
        (Wdrl Map.empty)
        0
        [asWitness Cast.bobPay, asWitness Cast.carlPay, asWitness Cast.dariaPay]

testEverybodySigns :: Assertion
testEverybodySigns =
  assertBool s (isRight utxoSt')
  where
    p :: Proxy C
    p = Proxy
    utxoSt' =
      applyTxWithScript
        p
        [(aliceOnly p, 11000)]
        [aliceOnly p]
        (Wdrl Map.empty)
        0
        [ asWitness Cast.alicePay,
          asWitness Cast.bobPay,
          asWitness Cast.carlPay,
          asWitness Cast.dariaPay
        ]
    s = "problem: " ++ show utxoSt'

testWrongScript :: Assertion
testWrongScript =
  utxoSt' @?= Left [[MissingScriptWitnessesUTXOW (Set.singleton $ hashScript (aliceOnly p))]]
  where
    p :: Proxy C
    p = Proxy
    utxoSt' =
      applyTxWithScript
        p
        [(aliceOnly p, 11000)]
        [aliceOrBob p]
        (Wdrl Map.empty)
        0
        [asWitness Cast.alicePay, asWitness Cast.bobPay]

testAliceOrBob :: Assertion
testAliceOrBob =
  assertBool s (isRight utxoSt')
  where
    p :: Proxy C
    p = Proxy
    utxoSt' =
      applyTxWithScript p [(aliceOrBob p, 11000)] [aliceOrBob p] (Wdrl Map.empty) 0 [asWitness Cast.alicePay]
    s = "problem: " ++ show utxoSt'

testAliceOrBob' :: Assertion
testAliceOrBob' =
  assertBool s (isRight utxoSt')
  where
    p :: Proxy C
    p = Proxy
    utxoSt' =
      applyTxWithScript p [(aliceOrBob p, 11000)] [aliceOrBob p] (Wdrl Map.empty) 0 [asWitness Cast.bobPay]
    s = "problem: " ++ show utxoSt'

testAliceAndBob :: Assertion
testAliceAndBob =
  assertBool s (isRight utxoSt')
  where
    p :: Proxy C
    p = Proxy
    utxoSt' =
      applyTxWithScript
        p
        [(aliceAndBob p, 11000)]
        [aliceAndBob p]
        (Wdrl Map.empty)
        0
        [asWitness Cast.alicePay, asWitness Cast.bobPay]
    s = "problem: " ++ show utxoSt'

testAliceAndBob' :: Assertion
testAliceAndBob' =
  utxoSt' @?= Left [[ScriptWitnessNotValidatingUTXOW (Set.singleton $ hashScript (aliceAndBob p))]]
  where
    p :: Proxy C
    p = Proxy
    utxoSt' =
      applyTxWithScript p [(aliceAndBob p, 11000)] [aliceAndBob p] (Wdrl Map.empty) 0 [asWitness Cast.alicePay]

testAliceAndBob'' :: Assertion
testAliceAndBob'' =
  utxoSt' @?= Left [[ScriptWitnessNotValidatingUTXOW (Set.singleton $ hashScript (aliceAndBob p))]]
  where
    p :: Proxy C
    p = Proxy
    utxoSt' =
      applyTxWithScript p [(aliceAndBob p, 11000)] [aliceAndBob p] (Wdrl Map.empty) 0 [asWitness Cast.bobPay]

testAliceAndBobOrCarl :: Assertion
testAliceAndBobOrCarl =
  assertBool s (isRight utxoSt')
  where
    p :: Proxy C
    p = Proxy
    utxoSt' =
      applyTxWithScript
        p
        [(aliceAndBobOrCarl p, 11000)]
        [aliceAndBobOrCarl p]
        (Wdrl Map.empty)
        0
        [asWitness Cast.alicePay, asWitness Cast.bobPay]
    s = "problem: " ++ show utxoSt'

testAliceAndBobOrCarl' :: Assertion
testAliceAndBobOrCarl' =
  assertBool s (isRight utxoSt')
  where
    p :: Proxy C
    p = Proxy
    utxoSt' =
      applyTxWithScript p [(aliceAndBobOrCarl p, 11000)] [aliceAndBobOrCarl p] (Wdrl Map.empty) 0 [asWitness Cast.carlPay]
    s = "problem: " ++ show utxoSt'

testAliceAndBobOrCarlAndDaria :: Assertion
testAliceAndBobOrCarlAndDaria =
  assertBool s (isRight utxoSt')
  where
    p :: Proxy C
    p = Proxy
    utxoSt' =
      applyTxWithScript
        p
        [(aliceAndBobOrCarlAndDaria p, 11000)]
        [aliceAndBobOrCarlAndDaria p]
        (Wdrl Map.empty)
        0
        [asWitness Cast.alicePay, asWitness Cast.bobPay]
    s = "problem: " ++ show utxoSt'

testAliceAndBobOrCarlAndDaria' :: Assertion
testAliceAndBobOrCarlAndDaria' =
  assertBool s (isRight utxoSt')
  where
    p :: Proxy C
    p = Proxy
    utxoSt' =
      applyTxWithScript
        p
        [(aliceAndBobOrCarlAndDaria p, 11000)]
        [aliceAndBobOrCarlAndDaria p]
        (Wdrl Map.empty)
        0
        [asWitness Cast.carlPay, asWitness Cast.dariaPay]
    s = "problem: " ++ show utxoSt'

testAliceAndBobOrCarlOrDaria :: Assertion
testAliceAndBobOrCarlOrDaria =
  assertBool s (isRight utxoSt')
  where
    p :: Proxy C
    p = Proxy
    utxoSt' =
      applyTxWithScript
        p
        [(aliceAndBobOrCarlOrDaria p, 11000)]
        [aliceAndBobOrCarlOrDaria p]
        (Wdrl Map.empty)
        0
        [asWitness Cast.alicePay, asWitness Cast.bobPay]
    s = "problem: " ++ show utxoSt'

testAliceAndBobOrCarlOrDaria' :: Assertion
testAliceAndBobOrCarlOrDaria' =
  assertBool s (isRight utxoSt')
  where
    p :: Proxy C
    p = Proxy
    utxoSt' =
      applyTxWithScript
        p
        [(aliceAndBobOrCarlOrDaria p, 11000)]
        [aliceAndBobOrCarlOrDaria p]
        (Wdrl Map.empty)
        0
        [asWitness Cast.carlPay]
    s = "problem: " ++ show utxoSt'

testAliceAndBobOrCarlOrDaria'' :: Assertion
testAliceAndBobOrCarlOrDaria'' =
  assertBool s (isRight utxoSt')
  where
    p :: Proxy C
    p = Proxy
    utxoSt' =
      applyTxWithScript
        p
        [(aliceAndBobOrCarlOrDaria p, 11000)]
        [aliceAndBobOrCarlOrDaria p]
        (Wdrl Map.empty)
        0
        [asWitness Cast.dariaPay]
    s = "problem: " ++ show utxoSt'

-- multiple script-locked outputs

testTwoScripts :: Assertion
testTwoScripts =
  assertBool s (isRight utxoSt')
  where
    p :: Proxy C
    p = Proxy
    utxoSt' =
      applyTxWithScript
        p
        [ (aliceOrBob p, 10000),
          (aliceAndBobOrCarl p, 1000)
        ]
        [ aliceOrBob p,
          aliceAndBobOrCarl p
        ]
        (Wdrl Map.empty)
        0
        [asWitness Cast.bobPay, asWitness Cast.carlPay]
    s = "problem: " ++ show utxoSt'

testTwoScripts' :: Assertion
testTwoScripts' =
  utxoSt' @?= Left [[ScriptWitnessNotValidatingUTXOW (Set.singleton $ hashScript (aliceAndBob p))]]
  where
    p :: Proxy C
    p = Proxy
    utxoSt' =
      applyTxWithScript
        p
        [ (aliceAndBob p, 10000),
          (aliceAndBobOrCarl p, 1000)
        ]
        [ aliceAndBob p,
          aliceAndBobOrCarl p
        ]
        (Wdrl Map.empty)
        0
        [asWitness Cast.bobPay, asWitness Cast.carlPay]

-- script and skey locked

testScriptAndSKey :: Assertion
testScriptAndSKey =
  assertBool s (isRight utxoSt')
  where
    p :: Proxy C
    p = Proxy
    utxoSt' =
      applyTxWithScript
        p
        [(aliceAndBob p, 10000)]
        [aliceAndBob p]
        (Wdrl Map.empty)
        1000
        [asWitness Cast.alicePay, asWitness Cast.bobPay]
    s = "problem: " ++ show utxoSt'

testScriptAndSKey' :: Assertion
testScriptAndSKey' =
  utxoSt'
    @?= Left
      [ [ MissingVKeyWitnessesUTXOW $
            WitHashes wits
        ]
      ]
  where
    p :: Proxy C
    p = Proxy
    utxoSt' =
      applyTxWithScript
        p
        [(aliceOrBob p, 10000)]
        [aliceOrBob p]
        (Wdrl Map.empty)
        1000
        [asWitness Cast.bobPay]
    wits = Set.singleton $ asWitness $ hashKey $ vKey Cast.alicePay

testScriptAndSKey'' :: Assertion
testScriptAndSKey'' =
  assertBool s (isRight utxoSt')
  where
    p :: Proxy C
    p = Proxy
    utxoSt' =
      applyTxWithScript
        p
        [(aliceOrBob p, 10000)]
        [aliceOrBob p]
        (Wdrl Map.empty)
        1000
        [asWitness Cast.alicePay]
    s = "problem: " ++ show utxoSt'

testScriptAndSKey''' :: Assertion
testScriptAndSKey''' =
  assertBool s (isRight utxoSt')
  where
    p :: Proxy C
    p = Proxy
    utxoSt' =
      applyTxWithScript
        p
        [(aliceAndBobOrCarl p, 10000)]
        [aliceAndBobOrCarl p]
        (Wdrl Map.empty)
        1000
        [asWitness Cast.alicePay, asWitness Cast.carlPay]
    s = "problem: " ++ show utxoSt'

-- Withdrawals

testRwdAliceSignsAlone :: Assertion
testRwdAliceSignsAlone =
  assertBool s (isRight utxoSt')
  where
    p :: Proxy C
    p = Proxy
    utxoSt' =
      applyTxWithScript
        p
        [(aliceOnly p, 11000)]
        [aliceOnly p]
        (Wdrl $ Map.singleton (RewardAcnt Testnet (ScriptHashObj $ hashScript (aliceOnly p))) 1000)
        0
        [asWitness Cast.alicePay]
    s = "problem: " ++ show utxoSt'

testRwdAliceSignsAlone' :: Assertion
testRwdAliceSignsAlone' =
  utxoSt' @?= Left [[ScriptWitnessNotValidatingUTXOW (Set.singleton $ hashScript (bobOnly p))]]
  where
    p :: Proxy C
    p = Proxy
    utxoSt' =
      applyTxWithScript
        p
        [(aliceOnly p, 11000)]
        [aliceOnly p, bobOnly p]
        (Wdrl $ Map.singleton (RewardAcnt Testnet (ScriptHashObj $ hashScript (bobOnly p))) 1000)
        0
        [asWitness Cast.alicePay]

testRwdAliceSignsAlone'' :: Assertion
testRwdAliceSignsAlone'' =
  assertBool s (isRight utxoSt')
  where
    p :: Proxy C
    p = Proxy
    utxoSt' =
      applyTxWithScript
        p
        [(aliceOnly p, 11000)]
        [aliceOnly p, bobOnly p]
        (Wdrl $ Map.singleton (RewardAcnt Testnet (ScriptHashObj $ hashScript (bobOnly p))) 1000)
        0
        [asWitness Cast.alicePay, asWitness Cast.bobPay]
    s = "problem: " ++ show utxoSt'

testRwdAliceSignsAlone''' :: Assertion
testRwdAliceSignsAlone''' =
  utxoSt' @?= Left [[MissingScriptWitnessesUTXOW (Set.singleton $ hashScript (bobOnly p))]]
  where
    p :: Proxy C
    p = Proxy
    utxoSt' =
      applyTxWithScript
        p
        [(aliceOnly p, 11000)]
        [aliceOnly p]
        (Wdrl $ Map.singleton (RewardAcnt Testnet (ScriptHashObj $ hashScript (bobOnly p))) 1000)
        0
        [asWitness Cast.alicePay, asWitness Cast.bobPay]