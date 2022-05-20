require("babel-core/register");
require("babel-polyfill");
require("jquery");

var commonModule = (function () {
    var pub = {};

    const tokenAddress = "0x633A3d2091dc7982597A0f635d23Ba5EB1223f48";
    const tokenSymbol = "FRY";
    const tokenDecimals = 18;
    const tokenImage = "https://foundrydao.com/common-assets/img/fry-icon.png";

    pub.addFryToMetaMask = () => {
        ethereum.sendAsync(
            {
                method: "wallet_watchAsset",
                params: {
                    type: "ERC20",
                    options: {
                        address: tokenAddress,
                        symbol: tokenSymbol,
                        decimals: tokenDecimals,
                        image: tokenImage,
                    },
                },
                id: 1,
            },
            (err, added) => {
                if (added) {
                    console.log("FRY token added to wallet");
                } else {
                    console.log("FRY token not added to wallet");
                }
            }
        );
    };

    return pub;
})();

module.exports = commonModule;
