port module BucketSale.State exposing (fetchFastGasPriceCmd, init, log, runCmdDown, subscriptions, update)

import BigInt exposing (BigInt)
import BucketSale.Types exposing (..)
import ChainCmd exposing (ChainCmd)
import CmdDown exposing (CmdDown)
import CmdUp exposing (CmdUp)
import Common.Types exposing (..)
import Config exposing (forbiddenJurisdictionCodes)
import Contracts.BucketSale.Wrappers as BucketSaleWrappers
import Contracts.MultiBucket.Wrappers as MultiBucketWrappers
import Contracts.Wrappers as TokenWrappers
import Css exposing (Display)
import Dict exposing (Dict)
import Element exposing (Element)
import Element.Font
import ElementHelpers as EH
import Eth
import Eth.Net
import Eth.Types exposing (Address, HttpProvider, Tx, TxHash, TxReceipt)
import Eth.Utils
import Helpers.BigInt as BigIntHelpers
import Helpers.Eth as EthHelpers
import Helpers.Http as HttpHelpers
import Helpers.Time as TimeHelpers
import Http
import Json.Decode
import Json.Decode.Extra
import Json.Encode
import List.Extra
import Maybe.Extra
import Result.Extra
import SelectHttpProvider exposing (..)
import Set
import Task
import Theme
import Time
import TokenValue exposing (TokenValue)
import Utils
import Wallet


init :
    EH.DisplayProfile
    -> BucketSale
    -> Maybe Address
    -> TestMode
    -> Wallet.State
    -> Time.Posix
    -> ( Model, Cmd Msg )
init dProfile bucketSale maybeReferrer testMode wallet now =
    ( { wallet =
            verifyWalletCorrectNetwork
                wallet
                testMode
      , extraUserInfo = Nothing
      , testMode = testMode
      , now = now
      , fastGasPrice = Nothing
      , saleStartTime = Nothing
      , bucketSale = bucketSale
      , totalTokensExited = Nothing
      , bucketView = ViewCurrent
      , jurisdictionCheckStatus = WaitingForClick
      , enterUXModel =
            initEnterUXModel
                maybeReferrer
      , trackedTxs = []
      , confirmTosModel =
            initConfirmTosModel
                dProfile
      , enterInfoToConfirm = Nothing
      , showReferralModal = False
      , showFeedbackUXModel = False
      , feedbackUXModel =
            initFeedbackUXModel
      , showYoutubeBlock = False
      , saleType = Standard
      }
    , Cmd.batch
        [ fetchFastGasPriceCmd
        , fetchStateUpdateInfoCmd
            (Wallet.userInfo wallet)
            Nothing
            Standard
            testMode
        , fetchBucketDataCmd
            (getCurrentBucketId
                bucketSale
                now
                testMode
            )
            (Wallet.userInfo wallet)
            testMode
        ]
    )


initConfirmTosModel :
    EH.DisplayProfile
    -> ConfirmTosModel
initConfirmTosModel dProfile =
    { points =
        tosLines dProfile
            |> (List.map >> List.map)
                (\( text, maybeAgreeText ) ->
                    TosCheckbox
                        text
                        (maybeAgreeText
                            |> Maybe.map
                                (\agreeText -> ( agreeText, False ))
                        )
                )
    , page = 0
    }


verifyWalletCorrectNetwork :
    Wallet.State
    -> TestMode
    -> Wallet.State
verifyWalletCorrectNetwork wallet testMode =
    case ( testMode, Wallet.network wallet ) of
        ( None, Just Eth.Net.Mainnet ) ->
            wallet

        ( TestMainnet, Just Eth.Net.Mainnet ) ->
            wallet

        ( TestKovan, Just Eth.Net.Kovan ) ->
            wallet

        ( TestGanache, Just (Eth.Net.Private 123456) ) ->
            wallet

        ( TestArbitrum, Just (Eth.Net.Private 421611) ) ->
            wallet

        ( None, Just Eth.Net.Kovan ) ->
            Wallet.WrongNetwork

        _ ->
            Wallet.NoneDetected


initEnterUXModel :
    Maybe Address
    -> EnterUXModel
initEnterUXModel maybeReferrer =
    { amountInput = ""
    , amountValidated = Nothing
    , fromBucketInput = ""
    , nrBucketsInput = ""
    , fromBucketValidated = Nothing
    , nrBucketsValidated = Nothing
    }


update :
    Msg
    -> Model
    -> UpdateResult
update msg prevModel =
    case msg of
        NoOp ->
            justModelUpdate prevModel
                Cmd.none

        CmdUp cmdUp ->
            UpdateResult
                prevModel
                Cmd.none
                ChainCmd.none
                [ cmdUp ]

        Refresh ->
            let
                fetchStateCmd =
                    fetchStateUpdateInfoCmd
                        (Wallet.userInfo prevModel.wallet)
                        (Just <| getFocusedBucketId prevModel.bucketSale prevModel.bucketView prevModel.now prevModel.testMode)
                        prevModel.saleType
                        prevModel.testMode

                checkTxsCmd =
                    prevModel.trackedTxs
                        |> List.indexedMap
                            (\id trackedTx ->
                                case trackedTx.status of
                                    Signed txHash Mining ->
                                        Just
                                            (Eth.getTxReceipt
                                                (appHttpProvider prevModel.testMode)
                                                txHash
                                                |> Task.attempt
                                                    (TxStatusFetched id trackedTx.action)
                                            )

                                    _ ->
                                        Nothing
                            )
                        |> Maybe.Extra.values
                        |> Cmd.batch
            in
            UpdateResult
                prevModel
                (Cmd.batch
                    [ fetchStateCmd
                    , checkTxsCmd
                    ]
                )
                ChainCmd.none
                []

        UpdateNow newNow ->
            let
                cmd =
                    case prevModel.bucketView of
                        ViewId _ ->
                            Cmd.none

                        ViewCurrent ->
                            let
                                newFocusedId =
                                    getCurrentBucketId prevModel.bucketSale newNow prevModel.testMode
                            in
                            if newFocusedId /= getCurrentBucketId prevModel.bucketSale prevModel.now prevModel.testMode then
                                fetchBucketDataCmd
                                    newFocusedId
                                    (Wallet.userInfo prevModel.wallet)
                                    prevModel.testMode

                            else
                                Cmd.none
            in
            UpdateResult
                { prevModel
                    | now = newNow
                }
                cmd
                ChainCmd.none
                []

        FetchFastGasPrice ->
            UpdateResult
                prevModel
                fetchFastGasPriceCmd
                ChainCmd.none
                []

        FetchedFastGasPrice fetchResult ->
            case fetchResult of
                Err httpErr ->
                    -- Just ignore it
                    justModelUpdate prevModel
                        (log "error fetching gasstation info")

                Ok fastGasPrice ->
                    justModelUpdate
                        { prevModel
                            | fastGasPrice = Just fastGasPrice
                        }
                        Cmd.none

        TosPreviousPageClicked ->
            justModelUpdate
                { prevModel
                    | confirmTosModel =
                        let
                            prevTosModel =
                                prevModel.confirmTosModel
                        in
                        { prevTosModel
                            | page =
                                max
                                    (prevTosModel.page - 1)
                                    0
                        }
                }
                Cmd.none

        TosNextPageClicked ->
            justModelUpdate
                { prevModel
                    | confirmTosModel =
                        let
                            prevTosModel =
                                prevModel.confirmTosModel
                        in
                        { prevTosModel
                            | page =
                                min
                                    (prevTosModel.page + 1)
                                    (List.length prevTosModel.points)
                        }
                }
                Cmd.none

        TosCheckboxClicked pointRef ->
            let
                newConfirmTosModel =
                    prevModel.confirmTosModel
                        |> toggleAssentForPoint pointRef
            in
            UpdateResult
                { prevModel
                    | confirmTosModel =
                        newConfirmTosModel
                }
                Cmd.none
                ChainCmd.none
                (if isAllPointsChecked newConfirmTosModel then
                    [ CmdUp.gTag
                        "7 - agree to all"
                        "funnel"
                        ""
                        0
                    ]

                 else
                    []
                )

        AddFryToMetaMaskClicked ->
            UpdateResult
                prevModel
                (addFryToMetaMask ())
                ChainCmd.none
                [ CmdUp.gTag
                    "10 - User requested exitingToken to be added to MetaMask"
                    "funnel"
                    ""
                    0
                ]

        VerifyJurisdictionClicked ->
            UpdateResult
                { prevModel
                    | jurisdictionCheckStatus = Checking
                }
                (beginLocationCheck ())
                ChainCmd.none
                [ CmdUp.gTag
                    "3a - verify jurisdiction clicked"
                    "funnel"
                    ""
                    0
                ]

        FeedbackButtonClicked ->
            justModelUpdate
                { prevModel
                    | showFeedbackUXModel = True
                }
                Cmd.none

        FeedbackEmailChanged newEmail ->
            justModelUpdate
                { prevModel
                    | feedbackUXModel =
                        let
                            prev =
                                prevModel.feedbackUXModel
                        in
                        { prev | email = newEmail }
                            |> updateAnyFeedbackUXErrors
                }
                Cmd.none

        FeedbackDescriptionChanged newDescription ->
            justModelUpdate
                { prevModel
                    | feedbackUXModel =
                        let
                            prev =
                                prevModel.feedbackUXModel
                        in
                        { prev | description = newDescription }
                            |> updateAnyFeedbackUXErrors
                }
                Cmd.none

        FeedbackSubmitClicked ->
            let
                prevFeedbackModel =
                    prevModel.feedbackUXModel
            in
            case validateFeedbackInput prevModel.feedbackUXModel of
                Ok validated ->
                    UpdateResult
                        { prevModel
                            | feedbackUXModel =
                                { prevFeedbackModel | sendState = Sending }
                        }
                        (sendFeedbackCmd validated Nothing)
                        ChainCmd.none
                        [ CmdUp.gTag
                            "feedback submitted"
                            "feedback"
                            (let
                                combinedStr =
                                    (validated.email |> Maybe.withDefault "[none]")
                                        ++ ":"
                                        ++ validated.description
                             in
                             combinedStr |> String.left 30
                            )
                            0
                        ]

                Err errStr ->
                    justModelUpdate
                        { prevModel
                            | feedbackUXModel =
                                { prevFeedbackModel | maybeError = Just errStr }
                        }
                        Cmd.none

        FeedbackHttpResponse responseResult ->
            let
                newFeedbackUX =
                    let
                        prevFeedbackUX =
                            prevModel.feedbackUXModel
                    in
                    case responseResult of
                        Err httpErr ->
                            { prevFeedbackUX
                                | sendState = SendFailed <| HttpHelpers.errorToString httpErr
                            }

                        Ok _ ->
                            { prevFeedbackUX
                                | sendState = Sent
                                , description = ""
                                , debugString = Nothing
                                , maybeError = Nothing
                            }
            in
            UpdateResult
                { prevModel | feedbackUXModel = newFeedbackUX }
                Cmd.none
                ChainCmd.none
                []

        FeedbackBackClicked ->
            justModelUpdate
                { prevModel
                    | showFeedbackUXModel = False
                }
                Cmd.none

        FeedbackSendMoreClicked ->
            justModelUpdate
                { prevModel
                    | feedbackUXModel =
                        let
                            prev =
                                prevModel.feedbackUXModel
                        in
                        { prev
                            | sendState = NotSent
                        }
                }
                Cmd.none

        LocationCheckResult decodeResult ->
            let
                jurisdictionCheckStatus =
                    locationCheckResultToJurisdictionStatus decodeResult
            in
            UpdateResult
                { prevModel
                    | jurisdictionCheckStatus = jurisdictionCheckStatus
                }
                Cmd.none
                ChainCmd.none
                (case jurisdictionCheckStatus of
                    WaitingForClick ->
                        []

                    Checking ->
                        []

                    Checked ForbiddenJurisdictions ->
                        [ CmdUp.gTag
                            "jurisdiction not allowed"
                            "funnel abort"
                            ""
                            0
                        ]

                    Checked _ ->
                        [ CmdUp.gTag
                            "3b - jurisdiction verified"
                            "funnel"
                            ""
                            0
                        ]

                    Error error ->
                        [ CmdUp.gTag
                            "failed jursidiction check"
                            "funnel abort"
                            error
                            0
                        ]
                )

        BucketValueEnteredFetched bucketId fetchResult ->
            case fetchResult of
                Err httpErr ->
                    justModelUpdate prevModel
                        (log "http error when fetching total bucket value entered")

                Ok valueEntered ->
                    let
                        maybeNewBucketSale =
                            prevModel.bucketSale
                                |> updateBucketAt
                                    bucketId
                                    (\bucket ->
                                        { bucket | totalValueEntered = Just valueEntered }
                                    )
                    in
                    case maybeNewBucketSale of
                        Nothing ->
                            justModelUpdate prevModel
                                (log "Warning! Somehow trying to update a bucket that doesn't exist!")

                        Just newBucketSale ->
                            justModelUpdate
                                { prevModel
                                    | bucketSale =
                                        newBucketSale
                                }
                                Cmd.none

        UserBuyFetched userAddress bucketId fetchResult ->
            if (Wallet.userInfo prevModel.wallet |> Maybe.map .address) /= Just userAddress then
                justModelUpdate prevModel
                    Cmd.none

            else
                case fetchResult of
                    Err httpErr ->
                        justModelUpdate prevModel
                            (log "http error when fetching buy for user")

                    Ok bindingBuy ->
                        let
                            buy =
                                buyFromBindingBuy bindingBuy
                        in
                        let
                            maybeNewBucketSale =
                                prevModel.bucketSale
                                    |> updateBucketAt
                                        bucketId
                                        (\bucket ->
                                            { bucket
                                                | userBuy = Just buy
                                            }
                                        )
                        in
                        case maybeNewBucketSale of
                            Nothing ->
                                justModelUpdate prevModel
                                    (log "Warning! Somehow trying to update a bucket that does not exist or is in the future!")

                            Just newBucketSale ->
                                justModelUpdate
                                    { prevModel | bucketSale = newBucketSale }
                                    Cmd.none

        StateUpdateInfoFetched fetchResult ->
            case fetchResult of
                Err httpErr ->
                    justModelUpdate prevModel
                        (log ("http error when fetching stateUpdateInfo "))

                Ok Nothing ->
                    justModelUpdate prevModel
                        (log "Query contract returned an invalid result")

                Ok (Just stateUpdateInfo) ->
                    let
                        newModel =
                            prevModel
                                |> (\model ->
                                        case Wallet.userInfo prevModel.wallet of
                                            Nothing ->
                                                prevModel

                                            Just userInfo ->
                                                case stateUpdateInfo.maybeUserStateInfo of
                                                    Nothing ->
                                                        prevModel

                                                    Just fetchedUserStateInfo ->
                                                        if Tuple.first fetchedUserStateInfo /= userInfo.address then
                                                            prevModel

                                                        else
                                                            { prevModel
                                                                | extraUserInfo =
                                                                    Just <| Tuple.second <| fetchedUserStateInfo
                                                            }
                                   )
                                |> (\model ->
                                        let
                                            maybeNewBucketSale =
                                                prevModel.bucketSale
                                                    |> updateBucketAt
                                                        stateUpdateInfo.bucketInfo.bucketId
                                                        (\bucket ->
                                                            { bucket
                                                                | userBuy =
                                                                    Just <|
                                                                        { valueEntered = stateUpdateInfo.bucketInfo.userTokensEntered
                                                                        , hasExited = not <| TokenValue.isZero stateUpdateInfo.bucketInfo.userTokensExited
                                                                        }
                                                                , totalValueEntered = Just stateUpdateInfo.bucketInfo.totalTokensEntered
                                                            }
                                                        )
                                        in
                                        case maybeNewBucketSale of
                                            Nothing ->
                                                --Debug.log "Warning! Somehow trying to update a bucket that does not exist or is in the future!" ""
                                                model

                                            Just newBucketSale ->
                                                { model | bucketSale = newBucketSale }
                                   )
                                |> (\model ->
                                        { model
                                            | totalTokensExited = Just stateUpdateInfo.totalTokensExited
                                        }
                                   )

                        ( ethBalance, enteringTokenBalance ) =
                            case stateUpdateInfo.maybeUserStateInfo of
                                Nothing ->
                                    ( TokenValue.zero
                                    , TokenValue.zero
                                    )

                                Just userStateInfo ->
                                    ( Tuple.second userStateInfo |> .ethBalance
                                    , Tuple.second userStateInfo |> .enteringTokenBalance
                                    )
                    in
                    UpdateResult
                        newModel
                        Cmd.none
                        ChainCmd.none
                        ((if not <| TokenValue.isZero ethBalance then
                            [ CmdUp.nonRepeatingGTag
                                "2a - has ETH"
                                "funnel"
                                ""
                                (ethBalance |> TokenValue.toFloatWithWarning |> floor)
                            ]

                          else
                            []
                         )
                            ++ (if not <| TokenValue.isZero enteringTokenBalance then
                                    [ CmdUp.nonRepeatingGTag
                                        ("2b - has " ++ Config.enteringTokenCurrencyLabel)
                                        "funnel"
                                        ""
                                        (enteringTokenBalance |> TokenValue.toFloatWithWarning |> floor)
                                    ]

                                else
                                    []
                               )
                        )

        TotalTokensExitedFetched fetchResult ->
            case fetchResult of
                Err httpErr ->
                    justModelUpdate prevModel
                        (log "http error when fetching totalTokensExited")

                Ok totalTokensExited ->
                    justModelUpdate
                        { prevModel
                            | totalTokensExited = Just totalTokensExited
                        }
                        Cmd.none

        FocusToBucket bucketId ->
            let
                newBucketView =
                    if bucketId == getCurrentBucketId prevModel.bucketSale prevModel.now prevModel.testMode then
                        ViewCurrent

                    else
                        ViewId
                            (bucketId
                                |> min (Config.bucketSaleNumBuckets - 1)
                                |> max 0
                            )

                maybeFetchBucketDataCmd =
                    let
                        bucketInfo =
                            getBucketInfo
                                prevModel.bucketSale
                                (getFocusedBucketId
                                    prevModel.bucketSale
                                    newBucketView
                                    prevModel.now
                                    prevModel.testMode
                                )
                                prevModel.now
                                prevModel.testMode
                    in
                    case bucketInfo of
                        ValidBucket bucketData ->
                            fetchBucketDataCmd
                                bucketId
                                (Wallet.userInfo prevModel.wallet)
                                prevModel.testMode

                        _ ->
                            Cmd.none
            in
            UpdateResult
                { prevModel
                    | bucketView = newBucketView
                }
                maybeFetchBucketDataCmd
                ChainCmd.none
                [ CmdUp.gTag "focus to bucket"
                    "navigation"
                    (String.fromInt bucketId)
                    1
                ]

        EnterInputChanged input ->
            UpdateResult
                { prevModel
                    | enterUXModel =
                        let
                            oldEnterUXModel =
                                prevModel.enterUXModel
                        in
                        { oldEnterUXModel
                            | amountInput = input
                            , amountValidated =
                                if input == "" then
                                    Nothing

                                else
                                    Just <| validateTokenInput input
                        }
                }
                Cmd.none
                ChainCmd.none
                [ CmdUp.gTag
                    "5? - enteringToken input changed"
                    "funnel"
                    input
                    0
                ]

        ReferralIndicatorClicked maybeReferrerAddress ->
            UpdateResult
                { prevModel
                    | showReferralModal =
                        if prevModel.showReferralModal then
                            False

                        else
                            True
                }
                Cmd.none
                ChainCmd.none
                [ CmdUp.gTag "modal shown" "referral" (maybeReferrerToString maybeReferrerAddress) 0 ]

        CloseReferralModal maybeReferrerAddress ->
            UpdateResult
                { prevModel
                    | showReferralModal = False
                }
                Cmd.none
                ChainCmd.none
                [ CmdUp.gTag "modal hidden" "referral" (maybeReferrerToString maybeReferrerAddress) 0 ]

        GenerateReferralClicked address ->
            UpdateResult
                prevModel
                Cmd.none
                ChainCmd.none
                [ CmdUp.NewReferralGenerated address
                , CmdUp.gTag "generate referral" "referral" (Eth.Utils.addressToString address) 0
                ]

        EnableTokenButtonClicked saleType ->
            let
                ( trackedTxId, newTrackedTxs ) =
                    prevModel.trackedTxs
                        |> trackNewTx
                            (TrackedTx
                                (Unlock saleType)
                                Signing
                            )

                chainCmd =
                    let
                        customSend =
                            { onMined = Nothing
                            , onSign =
                                Just <|
                                    TxSigned
                                        trackedTxId
                                        (Unlock saleType)
                            , onBroadcast = Nothing
                            }

                        txParams =
                            BucketSaleWrappers.approveTransfer
                                prevModel.testMode
                                saleType
                                |> Eth.toSend
                    in
                    ChainCmd.custom customSend txParams
            in
            UpdateResult
                { prevModel
                    | trackedTxs = newTrackedTxs
                }
                Cmd.none
                chainCmd
                [ CmdUp.gTag
                    "4a - unlock clicked"
                    "funnel"
                    ""
                    0
                ]

        EnterButtonClicked enterInfo ->
            UpdateResult
                { prevModel
                    | enterInfoToConfirm = Just enterInfo
                }
                Cmd.none
                ChainCmd.none
                [ CmdUp.gTag
                    "6 - enter clicked"
                    "funnel"
                    (TokenValue.toFloatString Nothing enterInfo.amount)
                    0
                ]

        CancelClicked ->
            UpdateResult
                { prevModel
                    | enterInfoToConfirm = Nothing
                }
                Cmd.none
                ChainCmd.none
                [ CmdUp.gTag
                    "tos aborted"
                    "funnel abort"
                    ""
                    0
                ]

        ConfirmClicked enterInfo ->
            let
                actionData =
                    Enter enterInfo

                ( trackedTxId, newTrackedTxs ) =
                    prevModel.trackedTxs
                        |> trackNewTx
                            (TrackedTx
                                actionData
                                Signing
                            )

                chainCmd =
                    let
                        customSend =
                            { onMined = Nothing
                            , onSign = Just <| TxSigned trackedTxId actionData
                            , onBroadcast = Nothing
                            }

                        txParams =
                            case enterInfo.saleType of
                                Standard ->
                                    BucketSaleWrappers.enter
                                        enterInfo.userInfo.address
                                        enterInfo.bucketId
                                        enterInfo.amount
                                        enterInfo.maybeReferrer
                                        prevModel.fastGasPrice
                                        prevModel.testMode
                                        |> Eth.toSend

                                Advanced ->
                                    -- userAddress bucketId amount numberOfBuckets maybeReferrer maybeGasPrice testMode
                                    MultiBucketWrappers.enter
                                        enterInfo.userInfo.address
                                        enterInfo.bucketId
                                        enterInfo.amount
                                        enterInfo.nrBuckets
                                        enterInfo.maybeReferrer
                                        prevModel.fastGasPrice
                                        prevModel.testMode
                                        |> Eth.toSend
                    in
                    ChainCmd.custom customSend txParams
            in
            UpdateResult
                { prevModel
                    | trackedTxs = newTrackedTxs
                    , enterInfoToConfirm = Nothing
                }
                Cmd.none
                chainCmd
                [ CmdUp.gTag
                    "8a - confirm clicked"
                    "funnel"
                    (TokenValue.toFloatString Nothing enterInfo.amount)
                    0
                ]

        ClaimClicked userInfo exitInfo saleType ->
            let
                ( trackedTxId, newTrackedTxs ) =
                    prevModel.trackedTxs
                        |> trackNewTx
                            (TrackedTx
                                Exit
                                Signing
                            )

                chainCmd =
                    let
                        customSend =
                            { onMined = Nothing
                            , onSign = Just <| TxSigned trackedTxId Exit
                            , onBroadcast = Nothing
                            }

                        txParams =
                            BucketSaleWrappers.exitMany
                                userInfo.address
                                exitInfo.exitableBuckets
                                prevModel.testMode
                                |> Eth.toSend
                    in
                    ChainCmd.custom customSend txParams
            in
            UpdateResult
                { prevModel
                    | trackedTxs = newTrackedTxs
                }
                Cmd.none
                chainCmd
                [ CmdUp.gTag
                    "claim clicked"
                    "after sale"
                    (exitInfo.totalExitable
                        |> TokenValue.toFloatString Nothing
                    )
                    0
                ]

        TxSigned trackedTxId actionData txHashResult ->
            case txHashResult of
                Err errStr ->
                    UpdateResult
                        { prevModel
                            | trackedTxs =
                                prevModel.trackedTxs
                                    |> updateTrackedTxStatus trackedTxId Rejected
                        }
                        Cmd.none
                        ChainCmd.none
                        [ CmdUp.gTag
                            (actionDataToString actionData ++ " tx sign error")
                            "funnel abort - tx"
                            errStr
                            0
                        , [ "Error signing tx"
                          , actionDataToString actionData
                          , errStr
                          ]
                            |> String.join "\n"
                            |> CmdUp.Log
                        ]

                Ok txHash ->
                    let
                        newTrackedTxs =
                            prevModel.trackedTxs
                                |> updateTrackedTxStatus trackedTxId (Signed txHash Mining)

                        newEnterUXModel =
                            case actionData of
                                Enter enterInfo ->
                                    let
                                        oldEnterUXModel =
                                            prevModel.enterUXModel
                                    in
                                    { oldEnterUXModel
                                        | amountInput = ""
                                        , amountValidated = Nothing
                                    }

                                _ ->
                                    prevModel.enterUXModel

                        ( funnelIdStr, maybeEventValue ) =
                            case actionData of
                                Unlock typeOfSale ->
                                    ( "4b - "
                                    , Nothing
                                    )

                                Enter enterInfo ->
                                    ( "8b - "
                                    , Just
                                        (enterInfo.amount
                                            |> TokenValue.toFloatWithWarning
                                        )
                                    )

                                Exit ->
                                    ( "9b - "
                                    , Nothing
                                    )
                    in
                    UpdateResult
                        { prevModel
                            | trackedTxs = newTrackedTxs
                            , enterUXModel = newEnterUXModel
                        }
                        (case maybeEventValue of
                            Just eventValue ->
                                tagTwitterConversion eventValue

                            Nothing ->
                                Cmd.none
                        )
                        ChainCmd.none
                        [ CmdUp.gTag
                            (funnelIdStr ++ actionDataToString actionData ++ " tx signed ")
                            "funnel - tx"
                            (Eth.Utils.txHashToString txHash)
                            (maybeEventValue |> Maybe.map floor |> Maybe.withDefault 0)
                        ]

        TxStatusFetched trackedTxId actionData fetchResult ->
            case fetchResult of
                Err _ ->
                    -- Usually indicates the tx has not yet been mined. Ignore and do nothing.
                    justModelUpdate
                        prevModel
                        Cmd.none

                Ok txReceipt ->
                    let
                        success =
                            -- the Maybe has to do with an Ethereum upgrade, far in the past, with which we need not concern ourselves
                            txReceipt.status |> Maybe.withDefault False

                        newSignedTxStatus =
                            if success then
                                Success

                            else
                                Failed

                        newTrackedTxs =
                            prevModel.trackedTxs
                                |> updateTrackedTxStatus trackedTxId
                                    (Signed txReceipt.hash newSignedTxStatus)

                        ( cmd, cmdUps ) =
                            case newSignedTxStatus of
                                Mining ->
                                    ( Cmd.none
                                    , []
                                    )

                                Success ->
                                    let
                                        ( funnelIdStr, maybeEventValue ) =
                                            case actionData of
                                                Unlock typeOfSale ->
                                                    ( "4c - "
                                                    , Nothing
                                                    )

                                                Enter enterInfo ->
                                                    ( "8c - "
                                                    , Just
                                                        (enterInfo.amount
                                                            |> TokenValue.toFloatWithWarning
                                                            |> floor
                                                        )
                                                    )

                                                Exit ->
                                                    ( "9c - "
                                                    , Nothing
                                                    )
                                    in
                                    ( let
                                        maybeBucketRefreshId =
                                            case actionData of
                                                Enter enterInfo ->
                                                    Just enterInfo.bucketId

                                                _ ->
                                                    Nothing
                                      in
                                      fetchStateUpdateInfoCmd
                                        (Wallet.userInfo prevModel.wallet)
                                        maybeBucketRefreshId
                                        prevModel.saleType
                                        prevModel.testMode
                                    , [ CmdUp.gTag
                                            (funnelIdStr ++ actionDataToString actionData ++ " tx success")
                                            "funnel - tx"
                                            (Eth.Utils.txHashToString txReceipt.hash)
                                            (maybeEventValue |> Maybe.withDefault 0)
                                      ]
                                    )

                                Failed ->
                                    ( Cmd.none
                                    , [ CmdUp.gTag
                                            (actionDataToString actionData ++ " tx failed")
                                            "funnel abort - tx"
                                            (Eth.Utils.txHashToString txReceipt.hash)
                                            0
                                      ]
                                    )
                    in
                    UpdateResult
                        { prevModel | trackedTxs = newTrackedTxs }
                        cmd
                        ChainCmd.none
                        cmdUps

        YoutubeBlockClicked ->
            UpdateResult
                { prevModel
                    | showYoutubeBlock =
                        if prevModel.showYoutubeBlock == True then
                            False

                        else
                            True
                }
                Cmd.none
                ChainCmd.none
                []

        SaleTypeToggleClicked newSaleType ->
            UpdateResult
                { prevModel
                    | saleType = newSaleType
                    , extraUserInfo = Nothing
                }
                (fetchStateUpdateInfoCmd
                    (Wallet.userInfo prevModel.wallet)
                    Nothing
                    newSaleType
                    prevModel.testMode
                )
                ChainCmd.none
                []

        MultiBucketFromBucketChanged value ->
            UpdateResult
                { prevModel
                    | enterUXModel =
                        let
                            oldEnterUXModel =
                                prevModel.enterUXModel

                            newFromBucketId =
                                if value == "" then
                                    Nothing

                                else
                                    Just <|
                                        validateMultiBucketStartBucket
                                            value
                                            (getCurrentBucketId
                                                prevModel.bucketSale
                                                prevModel.now
                                                prevModel.testMode
                                            )
                        in
                        { oldEnterUXModel
                            | fromBucketInput = value
                            , fromBucketValidated =
                                newFromBucketId
                            , nrBucketsValidated =
                                if value == "" then
                                    Nothing

                                else
                                    Just <|
                                        validateMultiBucketNrOfBuckets
                                            oldEnterUXModel.nrBucketsInput
                                            value
                                            (getCurrentBucketId
                                                prevModel.bucketSale
                                                prevModel.now
                                                prevModel.testMode
                                            )
                        }
                }
                Cmd.none
                ChainCmd.none
                []

        MultiBucketNumberOfBucketsChanged value ->
            UpdateResult
                { prevModel
                    | enterUXModel =
                        let
                            oldEnterUXModel =
                                prevModel.enterUXModel
                        in
                        { oldEnterUXModel
                            | nrBucketsInput = value
                            , nrBucketsValidated =
                                if value == "" then
                                    Nothing

                                else
                                    Just <|
                                        validateMultiBucketNrOfBuckets
                                            value
                                            prevModel.enterUXModel.fromBucketInput
                                            (getCurrentBucketId
                                                prevModel.bucketSale
                                                prevModel.now
                                                prevModel.testMode
                                            )
                        }
                }
                Cmd.none
                ChainCmd.none
                []


runCmdDown :
    CmdDown
    -> Model
    -> UpdateResult
runCmdDown cmdDown prevModel =
    case cmdDown of
        CmdDown.UpdateWallet newWallet ->
            if prevModel.wallet == newWallet then
                justModelUpdate prevModel
                    Cmd.none

            else
                let
                    newBucketSale =
                        prevModel.bucketSale |> clearBucketSaleExitInfo
                in
                UpdateResult
                    { prevModel
                        | wallet = verifyWalletCorrectNetwork newWallet prevModel.testMode
                        , bucketSale = newBucketSale
                        , extraUserInfo = Nothing
                    }
                    (fetchStateUpdateInfoCmd
                        (Wallet.userInfo newWallet)
                        (Just <|
                            getFocusedBucketId
                                prevModel.bucketSale
                                prevModel.bucketView
                                prevModel.now
                                prevModel.testMode
                        )
                        prevModel.saleType
                        prevModel.testMode
                    )
                    ChainCmd.none
                    (case newWallet of
                        Wallet.NoneDetected ->
                            [ CmdUp.gTag
                                "no web3"
                                "funnel abort"
                                ""
                                0
                            ]

                        Wallet.OnlyNetwork _ ->
                            [ CmdUp.gTag
                                "1a - new wallet state - has web3"
                                "funnel"
                                ""
                                0
                            ]

                        Wallet.WrongNetwork ->
                            [ CmdUp.gTag
                                "1a - new wallet state - has web3"
                                "funnel"
                                ""
                                0
                            , CmdUp.gTag
                                "wrong network"
                                "funnel abort"
                                ""
                                0
                            ]

                        Wallet.Active userInfo ->
                            [ CmdUp.gTag
                                "1b - unlocked web3"
                                "funnel"
                                (Eth.Utils.addressToChecksumString userInfo.address)
                                0
                            ]
                    )

        -- CmdDown.UpdateReferral address ->
        --     UpdateResult
        --         { prevModel
        --             | enterUXModel =
        --                 let
        --                     prevEnterUXModel =
        --                         prevModel.enterUXModel
        --                 in
        --                 { prevEnterUXModel
        --                     | referrer = Just address
        --                 }
        --         }
        --         Cmd.none
        --         ChainCmd.none
        --         []
        CmdDown.CloseAnyDropdownsOrModals ->
            justModelUpdate
                prevModel
                Cmd.none


toggleAssentForPoint :
    ( Int, Int )
    -> ConfirmTosModel
    -> ConfirmTosModel
toggleAssentForPoint ( pageNum, pointNum ) prevTosModel =
    { prevTosModel
        | points =
            prevTosModel.points
                |> List.Extra.updateAt pageNum
                    (List.Extra.updateAt pointNum
                        (\point ->
                            { point
                                | maybeCheckedString =
                                    point.maybeCheckedString
                                        |> Maybe.map
                                            (\( checkboxText, isChecked ) ->
                                                ( checkboxText
                                                , not isChecked
                                                )
                                            )
                            }
                        )
                    )
    }


fetchBucketDataCmd :
    Int
    -> Maybe UserInfo
    -> TestMode
    -> Cmd Msg
fetchBucketDataCmd id maybeUserInfo testMode =
    Cmd.batch
        [ fetchTotalValueEnteredCmd id testMode
        , case maybeUserInfo of
            Just userInfo ->
                fetchBucketUserBuyCmd id userInfo testMode

            Nothing ->
                Cmd.none
        ]


fetchTotalValueEnteredCmd :
    Int
    -> TestMode
    -> Cmd Msg
fetchTotalValueEnteredCmd id testMode =
    BucketSaleWrappers.getTotalValueEnteredForBucket
        testMode
        id
        (BucketValueEnteredFetched id)


fetchBucketUserBuyCmd :
    Int
    -> UserInfo
    -> TestMode
    -> Cmd Msg
fetchBucketUserBuyCmd id userInfo testMode =
    BucketSaleWrappers.getUserBuyForBucket
        testMode
        userInfo.address
        id
        (UserBuyFetched userInfo.address id)


fetchTotalTokensExitedCmd :
    TestMode
    -> Cmd Msg
fetchTotalTokensExitedCmd testMode =
    BucketSaleWrappers.getTotalExitedTokens
        testMode
        TotalTokensExitedFetched


fetchStateUpdateInfoCmd :
    Maybe UserInfo
    -> Maybe Int
    -> SaleType
    -> TestMode
    -> Cmd Msg
fetchStateUpdateInfoCmd maybeUserInfo maybeBucketId saleType testMode =
    BucketSaleWrappers.getStateUpdateInfo
        testMode
        (maybeUserInfo |> Maybe.map .address)
        (maybeBucketId
            |> Maybe.withDefault 0
        )
        saleType
        StateUpdateInfoFetched


fetchFastGasPriceCmd : Cmd Msg
fetchFastGasPriceCmd =
    Http.get
        { url = Config.gasstationApiEndpoint
        , expect =
            Http.expectJson
                FetchedFastGasPrice
                fastGasPriceDecoder
        }


sendFeedbackCmd :
    ValidatedFeedbackInput
    -> Maybe String
    -> Cmd Msg
sendFeedbackCmd validatedFeedbackInput maybeDebugString =
    Http.request
        { method = "POST"
        , headers = []
        , url = Config.feedbackEndpointUrl
        , body =
            Http.jsonBody <| encodeFeedback validatedFeedbackInput
        , expect = Http.expectString FeedbackHttpResponse
        , timeout = Nothing
        , tracker = Nothing
        }


encodeFeedback :
    ValidatedFeedbackInput
    -> Json.Encode.Value
encodeFeedback feedback =
    Json.Encode.object
        [ ( "Id", Json.Encode.int 0 )
        , ( "Email", Json.Encode.string (feedback.email |> Maybe.withDefault "") )
        , ( "ProblemDescription", Json.Encode.string feedback.description )
        , ( "ModelData", Json.Encode.string (feedback.debugString |> Maybe.withDefault "") )
        ]


fastGasPriceDecoder : Json.Decode.Decoder BigInt
fastGasPriceDecoder =
    Json.Decode.field "fast" Json.Decode.float
        |> Json.Decode.map
            (\gweiTimes10 ->
                -- idk why, but ethgasstation returns units of gwei*10
                gweiTimes10 * 100000000
             -- multiply by (1 billion / 10) to get wei
            )
        |> Json.Decode.map floor
        |> Json.Decode.map BigInt.fromInt


clearBucketSaleExitInfo :
    BucketSale
    -> BucketSale
clearBucketSaleExitInfo =
    updateAllBuckets
        (\bucket ->
            { bucket | userBuy = Nothing }
        )


validateTokenInput :
    String
    -> Result String TokenValue
validateTokenInput input =
    case String.toFloat input of
        Just floatVal ->
            if floatVal <= 0 then
                Err "Value must be greater than 0"

            else
                Ok <| TokenValue.fromFloatWithWarning floatVal

        Nothing ->
            Err "Can't interpret that number"


validateMultiBucketStartBucket :
    String
    -> Int
    -> Result String Int
validateMultiBucketStartBucket fromBucket currentBucket =
    let
        rangeError =
            "Valid buckets are numbered 0 to 1999"
    in
    case String.toInt fromBucket of
        Just intVal ->
            if intVal < 0 || intVal > 1999 then
                Err rangeError

            else if intVal < currentBucket then
                Err <| "Cannot start before current bucket (" ++ String.fromInt currentBucket ++ ")"

            else
                Ok intVal

        Nothing ->
            Err rangeError


validateMultiBucketNrOfBuckets :
    String
    -> String
    -> Int
    -> Result String Int
validateMultiBucketNrOfBuckets nrBuckets fromBucket currentBucket =
    let
        validStartBucket =
            case validateMultiBucketStartBucket fromBucket currentBucket of
                Ok startBucket ->
                    startBucket

                _ ->
                    currentBucket

        maxRangeError =
            "Valid nr of buckets range between 1 and "

        maxBucketId =
            Config.bucketSaleNumBuckets - 1

        maxNrBuckets =
            Config.maxMultiBucketRange
    in
    case String.toInt nrBuckets of
        Just intVal ->
            if intVal < 1 || intVal > maxNrBuckets then
                Err <| maxRangeError ++ String.fromInt maxNrBuckets

            else if (validStartBucket + intVal - 1) > maxBucketId then
                Err <| "To bid on " ++ nrBuckets ++ " buckets starting bucket must be " ++ String.fromInt (maxBucketId + 1 - intVal)

            else
                Ok intVal

        Nothing ->
            Err <| maxRangeError ++ String.fromInt maxNrBuckets


trackNewTx :
    TrackedTx
    -> List TrackedTx
    -> ( Int, List TrackedTx )
trackNewTx newTrackedTx prevTrackedTxs =
    ( List.length prevTrackedTxs
    , List.append
        prevTrackedTxs
        [ newTrackedTx ]
    )


updateTrackedTxStatus :
    Int
    -> TxStatus
    -> List TrackedTx
    -> List TrackedTx
updateTrackedTxStatus id newStatus =
    List.Extra.updateAt id
        (\trackedTx ->
            { trackedTx | status = newStatus }
        )


locationCheckResultToJurisdictionStatus :
    Result Json.Decode.Error (Result String LocationInfo)
    -> JurisdictionCheckStatus
locationCheckResultToJurisdictionStatus decodeResult =
    decodeResult
        |> Result.map
            (\checkResult ->
                checkResult
                    |> Result.map
                        (\locationInfo ->
                            Checked <|
                                countryCodeToJurisdiction locationInfo.ipCode locationInfo.geoCode
                        )
                    |> Result.mapError
                        (\e ->
                            Error <|
                                "Location check failed: "
                                    ++ e
                        )
                    |> Result.Extra.merge
            )
        |> Result.mapError
            (\e -> Error <| "Location check response decode error: " ++ Json.Decode.errorToString e)
        |> Result.Extra.merge


countryCodeToJurisdiction :
    String
    -> String
    -> Jurisdiction
countryCodeToJurisdiction ipCode geoCode =
    let
        allowedJurisdiction =
            Set.fromList [ ipCode, geoCode ]
                |> Set.intersect forbiddenJurisdictionCodes
                |> Set.isEmpty
    in
    if allowedJurisdiction then
        JurisdictionsWeArentIntimidatedIntoExcluding

    else
        ForbiddenJurisdictions


locationCheckDecoder : Json.Decode.Decoder (Result String LocationInfo)
locationCheckDecoder =
    Json.Decode.oneOf
        [ Json.Decode.oneOf
            [ Json.Decode.field "errorMessage" Json.Decode.string
            , Json.Decode.field "ErrorMessage" Json.Decode.string
            ]
            |> Json.Decode.map
                (\str ->
                    Err <|
                        if str == "Unknown" then
                            "The jurisdiction check server is not responding. This shouldn't happen - please email support@foundrydao.com and we will respond quickly to resolve this."

                        else
                            str
                )
        , locationInfoDecoder
            |> Json.Decode.map Ok
        ]


locationInfoDecoder : Json.Decode.Decoder LocationInfo
locationInfoDecoder =
    Json.Decode.map2
        LocationInfo
        (Json.Decode.field "ipCountry" Json.Decode.string)
        (Json.Decode.field "geoCountry" Json.Decode.string)


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ Time.every 15000 <| always Refresh
        , Time.every 500 UpdateNow
        , Time.every (1000 * 60 * 10) <| always FetchFastGasPrice
        , locationCheckResult
            (Json.Decode.decodeValue locationCheckDecoder >> LocationCheckResult)
        ]


port beginLocationCheck : () -> Cmd msg


port locationCheckResult : (Json.Decode.Value -> msg) -> Sub msg


port addFryToMetaMask : () -> Cmd msg


port tagTwitterConversion : Float -> Cmd msg


tosLines : EH.DisplayProfile -> List (List ( List (Element Msg), Maybe String ))
tosLines dProfile =
    case dProfile of
        EH.Desktop ->
            [ [ ( [ Element.text "This constitutes an agreement between you and the Decentralized Autonomous Organization Advancement Institute (\"DAOAI\") ("
                  , Element.newTabLink
                        [ Element.Font.color Theme.blue ]
                        { url = "https://foundrydao.com/contact"
                        , label = Element.text "Contact info"
                        }
                  , Element.text ")."
                  ]
                , Just "I understand."
                )
              , ( List.singleton <| Element.text "You are an adult capable of making your own decisions, evaluating your own risks and engaging with others for mutual benefit."
                , Just "I agree."
                )
              , ( [ Element.text "A text version if this agreement can be found "
                  , Element.newTabLink
                        [ Element.Font.color Theme.blue ]
                        { url = "https://foundrydao.com/blog/sale-terms"
                        , label = Element.text "here"
                        }
                  , Element.text "."
                  ]
                , Nothing
                )
              ]
            , [ ( List.singleton <| Element.text "Foundry and/or FRY are extremely experimental and could enter into several failure modes."
                , Nothing
                )
              , ( List.singleton <| Element.text "Foundry and/or FRY could fail technically through a software vulnerability."
                , Just "I understand."
                )
              , ( List.singleton <| Element.text "While Foundry and/or FRY have been audited, bugs may have nonetheless snuck through."
                , Just "I understand."
                )
              , ( List.singleton <| Element.text "Foundry and/or FRY could fail due to an economic attack, the details of which might not even be suspected at the time of launch."
                , Just "I understand."
                )
              ]
            , [ ( List.singleton <| Element.text "The projects that Foundry funds may turn out to be flawed technically or have economic attack vectors that make them infeasible."
                , Just "I understand."
                )
              , ( List.singleton <| Element.text "FRY, and the projects funded by Foundry, might never find profitable returns."
                , Just "I understand."
                )
              ]
            , [ ( List.singleton <| Element.text "You will not hold DAOAI liable for damages or losses."
                , Just "I agree."
                )
              , ( List.singleton <| Element.text "Even if you did, DAOAI will be unlikely to have the resources to settle."
                , Just "I understand."
                )
              , ( List.singleton <| Element.text "DAI deposited into this will be held in smart contracts, which DAOAI might not have complete or significant control over."
                , Just "I understand."
                )
              ]
            , [ ( List.singleton <| Element.text "I agree Foundry may track anonymized data about my interactions with the sale."
                , Just "I understand."
                )
              , ( List.singleton <| Element.text "Entering DAI into the sale is irrevocable, even if the bucket has not yet concluded."
                , Just "I understand."
                )
              , ( List.singleton <| Element.text "US citizens and residents are strictly prohibited from this sale."
                , Just "I am not a citizen or resident of the USA."
                )
              ]
            ]

        EH.Mobile ->
            [ [ ( [ Element.paragraph
                        [ Element.Font.size 12 ]
                        [ Element.text "This constitutes an agreement between you and the Decentralized Autonomous Organization Advancement Institute (\"DAOAI\") ("
                        , Element.newTabLink
                            [ Element.Font.color Theme.blue ]
                            { url = "https://foundrydao.com/contact"
                            , label = Element.text "Contact info"
                            }
                        , Element.text ")."
                        ]
                  ]
                , Just "I understand."
                )
              , ( List.singleton <|
                    Element.paragraph
                        [ Element.Font.size 12 ]
                        [ Element.text "You are an adult capable of making your own decisions, evaluating your own risks and engaging with others for mutual benefit." ]
                , Just "I agree."
                )
              , ( [ Element.paragraph
                        [ Element.Font.size 12 ]
                        [ Element.text "A text version if this agreement can be found "
                        , Element.newTabLink
                            [ Element.Font.color Theme.blue ]
                            { url = "https://foundrydao.com/blog/sale-terms"
                            , label = Element.text "here"
                            }
                        , Element.text "."
                        ]
                  ]
                , Nothing
                )
              ]
            , [ ( List.singleton <|
                    Element.paragraph
                        [ Element.Font.size 12 ]
                        [ Element.text "Foundry and/or FRY are extremely experimental and could enter into several failure modes." ]
                , Nothing
                )
              , ( List.singleton <|
                    Element.paragraph
                        [ Element.Font.size 12 ]
                        [ Element.text "Foundry and/or FRY could fail technically through a software vulnerability." ]
                , Just "I understand."
                )
              , ( List.singleton <|
                    Element.paragraph
                        [ Element.Font.size 12 ]
                        [ Element.text "While Foundry and/or FRY have been audited, bugs may have nonetheless snuck through." ]
                , Just "I understand."
                )
              , ( List.singleton <|
                    Element.paragraph
                        [ Element.Font.size 12 ]
                        [ Element.text "Foundry and/or FRY could fail due to an economic attack, the details of which might not even be suspected at the time of launch." ]
                , Just "I understand."
                )
              ]
            , [ ( List.singleton <|
                    Element.paragraph
                        [ Element.Font.size 12 ]
                        [ Element.text "The projects that Foundry funds may turn out to be flawed technically or have economic attack vectors that make them infeasible." ]
                , Just "I understand."
                )
              , ( List.singleton <|
                    Element.paragraph
                        [ Element.Font.size 12 ]
                        [ Element.text "FRY, and the projects funded by Foundry, might never find profitable returns." ]
                , Just "I understand."
                )
              ]
            , [ ( List.singleton <|
                    Element.paragraph
                        [ Element.Font.size 12 ]
                        [ Element.text "You will not hold DAOAI liable for damages or losses." ]
                , Just "I agree."
                )
              , ( List.singleton <|
                    Element.paragraph
                        [ Element.Font.size 12 ]
                        [ Element.text "Even if you did, DAOAI will be unlikely to have the resources to settle." ]
                , Just "I understand."
                )
              , ( List.singleton <|
                    Element.paragraph
                        [ Element.Font.size 12 ]
                        [ Element.text "DAI deposited into this will be held in smart contracts, which DAOAI might not have complete or significant control over." ]
                , Just "I understand."
                )
              ]
            , [ ( List.singleton <|
                    Element.paragraph
                        [ Element.Font.size 12 ]
                        [ Element.text "I agree Foundry may track anonymized data about my interactions with the sale." ]
                , Just "I understand."
                )
              , ( List.singleton <|
                    Element.paragraph
                        [ Element.Font.size 12 ]
                        [ Element.text "Entering DAI into the sale is irrevocable, even if the bucket has not yet concluded." ]
                , Just "I understand."
                )
              , ( List.singleton <|
                    Element.paragraph
                        [ Element.Font.size 12 ]
                        [ Element.text "US citizens and residents are strictly prohibited from this sale." ]
                , Just "I am not a citizen or resident of the USA."
                )
              ]
            ]


port log : String -> Cmd msg
