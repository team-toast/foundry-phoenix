module Config exposing (..)

import BigInt exposing (BigInt)
import Common.Types exposing (..)
import Eth.Types exposing (Address)
import Eth.Utils
import Set exposing (Set)
import Time
import TokenValue exposing (TokenValue)


displayProfileBreakpoint : Int
displayProfileBreakpoint =
    1280


mainnetHttpProviderUrl : String
mainnetHttpProviderUrl =
    "https://arb1.arbitrum.io/rpc"
    -- "https://81fa4f6630764ea8aa60f0c535d71325.eth.rpc.rivet.cloud/"


kovanHttpProviderUrl : String
kovanHttpProviderUrl =
    "https://kovan.infura.io/v3/e3eef0e2435349bf9164e6f465bd7cf9"


ganacheProviderUrl : String
ganacheProviderUrl =
    "http://localhost:8545"

arbitrumTestProviderUrl : String
arbitrumTestProviderUrl =
    "https://rinkeby.arbitrum.io/rpc"


appTitle : String
appTitle =
    "FRY Sale - Join Foundry and become a FRY holder!"


enteringTokenCurrencyLabel : String
enteringTokenCurrencyLabel =
    "DAI"


enteringTokenImageInfo : { src : String, description : String }
enteringTokenImageInfo =
    { src = "img/dai-symbol.png"
    , description = "DAI"
    }

enteringTokenAddress : TestMode -> Address
enteringTokenAddress testMode =
    case testMode of
        None ->
            Eth.Utils.unsafeToAddress "0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1"

        TestKovan ->
            Eth.Utils.unsafeToAddress "0x0000000000000000000000000000000000000000"

        TestMainnet ->
            Eth.Utils.unsafeToAddress "0x6B175474E89094C44Da98b954EedeAC495271d0F"

        TestGanache ->
            Eth.Utils.unsafeToAddress "0x2612Af3A521c2df9EAF28422Ca335b04AdF3ac66"

        TestArbitrum ->
            Eth.Utils.unsafeToAddress "0x7446e9168C5c5B01c67e4c08d31A7fD00b9F99B5"


exitingTokenCurrencyLabel : String
exitingTokenCurrencyLabel =
    "FRY"


exitingTokenAddress : TestMode -> Address
exitingTokenAddress testMode =
    case testMode of
        None ->
            Eth.Utils.unsafeToAddress "0x633A3d2091dc7982597A0f635d23Ba5EB1223f48"

        TestKovan ->
            Eth.Utils.unsafeToAddress "0x0000000000000000000000000000000000000000"

        TestMainnet ->
            Eth.Utils.unsafeToAddress "0xe8c7495870f63DD045ba20E4604Ef3534ffa3724"

        TestGanache ->
            Eth.Utils.unsafeToAddress "0x67B5656d60a809915323Bf2C40A8bEF15A152e3e"

        TestArbitrum ->
            Eth.Utils.unsafeToAddress "0xfBDc22E286d92406D979ef161FdF696D9829A7aC"


bucketSaleAddress : TestMode -> Address
bucketSaleAddress testMode =
    case testMode of
        None ->
            Eth.Utils.unsafeToAddress "0x0000000000000000000000000000000000000000"
        
        TestKovan ->
            Eth.Utils.unsafeToAddress "0x0000000000000000000000000000000000000000"

        TestMainnet ->
            Eth.Utils.unsafeToAddress "0xEB997be36d9a3168e548f058FF6E76Ba16bd8d13"

        TestGanache ->
            Eth.Utils.unsafeToAddress "0x26b4AFb60d6C903165150C6F0AA14F8016bE4aec"

        TestArbitrum ->
            Eth.Utils.unsafeToAddress "0xA8f59986533cC92762244190C43eAC0c0E0ffe10"

bucketSaleScriptsAddress : TestMode -> Address
bucketSaleScriptsAddress testMode =
    case testMode of
        None ->
            Eth.Utils.unsafeToAddress "0x32901CB36289620e4DeB9D551770D5e19b9C7786"

        TestKovan ->
            Eth.Utils.unsafeToAddress "0x0000000000000000000000000000000000000000"

        TestMainnet ->
            Eth.Utils.unsafeToAddress "0xfF0E22aDd363A90bB5cAd3e74A21341C1a9A80AE"

        TestGanache ->
            Eth.Utils.unsafeToAddress "0x0000000000000000000000000000000000000000"

        TestArbitrum ->
            Eth.Utils.unsafeToAddress "0x67e9195998C10AAB6bb2a4Cfd59145906fda1efF"


gasstationApiEndpoint : String
gasstationApiEndpoint =
    "https://ethgasstation.info/api/ethgasAPI.json?api-key=ebca374685809a499c4513455cb6867c6112269da20bda9ae64d491a02cf"


bucketSaleBucketInterval : TestMode -> Time.Posix
bucketSaleBucketInterval testMode =
    Time.millisToPosix <| 1000 * 604800
    -- Time.millisToPosix <| 1000 * 7200


bucketSaleTokensPerBucket : TestMode -> TokenValue
bucketSaleTokensPerBucket testMode =
    TokenValue.fromIntTokenValue 2000000


bucketSaleNumBuckets : Int
bucketSaleNumBuckets =
    50


feedbackEndpointUrl : String
feedbackEndpointUrl =
    "https://personal-rxyx.outsystemscloud.com/SaleFeedbackUI/rest/General/SubmitFeedback"


ipCountryCodeEndpointUrl : String
ipCountryCodeEndpointUrl =
    "https://personal-rxyx.outsystemscloud.com/SaleFeedbackUI/rest/General/IPCountryLookup"


forbiddenJurisdictionCodes : Set String
forbiddenJurisdictionCodes =
    Set.fromList [ "US" ]


multiBucketBotAddress : TestMode -> Address
multiBucketBotAddress testMode =
    case testMode of
        None ->
            Eth.Utils.unsafeToAddress "0xA65424Bf9E63b1049380019F4C98dbe4Faa58d1F"

        TestKovan ->
            Eth.Utils.unsafeToAddress "0x0000000000000000000000000000000000000000"

        TestMainnet ->
            Eth.Utils.unsafeToAddress "0x7d6ea6ae58ddc0c237557035ad873b5a978d108b"

        TestGanache ->
            Eth.Utils.unsafeToAddress "0x0000000000000000000000000000000000000000"

        TestArbitrum ->
            Eth.Utils.unsafeToAddress "0x12871157a0cDd0c15F5513f0564953636fEFC935"


maxMultiBucketRange : Int
maxMultiBucketRange =
    50
