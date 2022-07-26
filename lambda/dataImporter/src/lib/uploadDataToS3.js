const aws = require("aws-sdk");
const { readFileSync } = require("node:fs");

const uploadDataToS3 = async (sourceFileName) => {
  const cloudGuardS3BuckedId = process.env.CLOUDGUARD_DATA_S3_BUCKET_ID;

  const protectedAssetsData = readFileSync("/tmp/" + sourceFileName);

  const s3Client = new aws.S3({ apiVersion: "2006-03-01" });

  const params = {
    Bucket: cloudGuardS3BuckedId,
    Key: "rawData/" + sourceFileName,
    Body: protectedAssetsData,
  };

  try {
    const response = await s3Client.upload(params).promise();
    console.log("Response: ", response);
    return response;
  } catch (err) {
    console.log(err);
    return {
      message: "An error occure saving to S3",
      error: JSON.stringify(err),
    };
  }
};
module.exports.uploadDataToS3 = uploadDataToS3;
