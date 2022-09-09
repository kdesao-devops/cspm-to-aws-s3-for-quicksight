const aws = require("aws-sdk");
const JSONStream = require("JSONStream");
const csvwriter = require('csv-writer');
const moment = require("moment");

const { getaccountlist } = require("./lib/getaccountlist");
const { uploadDataToS3 } = require("./lib/uploadDataToS3");

const dateTimeObject = new moment().format("YYYY-MMMM-DD");
const today = new Date();
var result = new Object();

// Used to pass from an object to a regular array
const dataflat = function (listunflat) {
  data_flat = [];
  Object.keys(listunflat).forEach(function (key, index) {
    data_flat.push(listunflat[key]);
  });
  return data_flat.flat();
};

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

module.exports.index = function () {
  const readfileName = `cloud-guard-protected-assets-${dateTimeObject}.json`;
  const readfilePath = "rawData/" + readfileName;

  const getStream = () => {
    var s3 = new aws.S3();
    var params = {
      Bucket: process.env.CLOUDGUARD_DATA_S3_BUCKET_ID,
      Key: readfilePath
    };

    let readStream = s3.getObject(params).createReadStream();

    const parser = JSONStream.parse("*");
    return readStream.pipe(parser);
  };

  getStream().on('error', function (error) {
    console.log(`error: ${error.message}`);
    return error;
  });

  getaccountlist().then((account_list) => {
    getStream().on('data', function (data) {
      account_id = data.externalCloudAccountId;
      type = data.type;
      account_name = account_list.find(v => v.Account_id == account_id).account_name;

      //On first run the array in result Object doesn't exist so it needs to be catch
      try {
        // if exist doing nothing
        typeof (result[account_id].find(v => v.type === type) === 'undefined')
      } catch (error) {
        // else init the list with 0 because it will be increment just after
        result[account_id] = []
        result[account_id].push({ "type": type, "quantity": 0, "date": today.toLocaleDateString(('en-US')), "account_id": account_id, "Account_name": account_name })
      };

      // Make the variable easier to access
      count_type = result[account_id].find(v => v.type === type)
      try {
        //If exist increment quantity
        count_type.quantity === 'number'
        count_type.quantity = count_type.quantity + 1 || 1
      } catch (error) {
        // Else we init the new type at one this time because the increment passed
        result[account_id].push({ "type": type, "quantity": 1, "date": today.toLocaleDateString(('en-US')), "account_id": account_id, "Account_name": account_name })
      }
    });
  })

  getStream().on('end', function () {
    // Writing the csv file locally
    sleep(50000).then(() => {
      const fileName = `cloud-guard-assets-${dateTimeObject}.csv`;
      const filePath = "/tmp/" + fileName

      const createCsvWriter = csvwriter.createObjectCsvWriter;
      const csvWriter = createCsvWriter({
        path: filePath,
        header: [
          { id: 'date', title: 'Date' },
          { id: 'account_id', title: 'Account ID' },
          { id: 'type', title: 'Type' },
          { id: 'quantity', title: 'Quantity' },
          { id: 'Account_name', title: 'Account Name' },
        ]
      });

      const assets_list = dataflat(result)

      csvWriter.writeRecords(assets_list).then(() => {
        try {
          uploadDataToS3(fileName).then((response) => {
            console.log('done');
          });
        } catch (err) {
          console.log(err);
        }
      });
    });
  });
};
