const axios = require("axios");
const awsClient = require("aws-sdk");
const { Buffer } = require("buffer");

const getProtectedAssets = async (searchAfter = [], pageSize = 1000) => {
  const cloudGuardApiEndpoint = process.env.CLOUDGUARD_API_ENDPOINT;
  const cloudGuardApiKeysParameterStore =
    process.env.CLOUDGUARD_API_KEYS_PARAMETER_STORE;
  const cloudGuardApiPageSize = process.env.CLOUDGUARD_PAGE_SIZE;

  const ssmClient = new awsClient.SSM({
    apiVersion: "2014-11-06",
    region: "ca-central-1",
  });

  let cloudGuardApiKeys = {};
  const ssmParams = {
    Name: `${cloudGuardApiKeysParameterStore}`,
    WithDecryption: true,
  };
  try {
    cloudGuardApiKeys = await ssmClient.getParameter(ssmParams).promise();
  } catch (err) {
    console.error(err);
  }

  let apiKeyObject = {};
  apiKeyObject = JSON.parse(cloudGuardApiKeys.Parameter.Value);

  const auth = Buffer.from(
    apiKeyObject.apiKeyId + ":" + apiKeyObject.apiKeySecret
  ).toString("base64");

  const axiosParams = {
    method: "post",
    url: `https://${cloudGuardApiEndpoint}/protected-asset/search`,
    headers: {
      "Content-Type": "application/json",
      Accept: "application/json",
      Authorization: "Basic " + auth,
    },
    data: {
      pageSize: `${cloudGuardApiPageSize}`,
      searchAfter: searchAfter,
    },
  };

  try {
    let response = await axios(axiosParams);
    // console.log(response);
    return response["data"];
  } catch (err) {
    console.error(err);
    return err;
  }
};
module.exports.getProtectedAssets = getProtectedAssets;
