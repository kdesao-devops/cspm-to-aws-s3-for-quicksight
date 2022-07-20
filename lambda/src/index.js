const { getProtectedAssets } = require("./lib/getProtectedAssets");
const { uploadDataToS3 } = require("./lib/uploadDataToS3");
const { createWriteStream } = require("node:fs");
const moment = require("moment");

module.exports.index = async () => {
  const dateTimeObject = new moment().format("YYYY-MMMM-DD-hhmmss");

  let fileName = `/tmp/cloud-guard-protected-assets-${dateTimeObject}.json`;
  let fileStream = createWriteStream(fileName);

  let searchAfter = [];
  let protectedAssets;

  try {
    protectedAssets = await getProtectedAssets();
    await fileStream.write(JSON.stringify(protectedAssets["assets"]), "utf-8");
    console.log({
      message: `Asset data successfully written to: ${fileName}`,
    });
  } catch (err) {
    console.log(err);
    console.error({
      message: `Error writing asset data to: ${fileName}`,
      error: err,
    });
    return {
      message: `Error writing asset data to: ${fileName}`,
      error: err,
    };
  }

  while (protectedAssets["searchAfter"]) {
    searchAfter = protectedAssets["searchAfter"];
    try {
      protectedAssets = await getProtectedAssets(searchAfter);
      await fileStream.write(
        JSON.stringify(protectedAssets["assets"]),
        "utf-8"
      );
    } catch (err) {
      console.log(err);
    }
  }

  try {
    await uploadDataToS3(fileName);
  } catch (err) {
    console.log(err);
  }
};
