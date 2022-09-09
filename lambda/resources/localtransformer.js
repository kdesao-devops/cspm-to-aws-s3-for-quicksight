// This is a local version of the datatransformer Lambda. It has been created to be able to Test.
// To be used it required access to the awslz2 account the readonly account can be used for more safety
// Also the variable about the date and the filename have to be changed

const csvwriter = require('csv-writer');
const aws = require("aws-sdk");
const fs = require('fs')
const JSONStream = require("JSONStream");

// Variable to change to adapt to the aimed file:
const today = '9/8/2022';
const file_date = '2022-September-08';
const RawFileName = 'raw/cloud-guard-protected-assets-' + file_date + '.json';
const CSVFilePath = 'cloud-guard-assets-' + file_date + '.csv';

var result = new Object();

function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

const dataflat = function (listunflat) {
    data_flat = [];
    Object.keys(listunflat).forEach(function (key, index) {
        data_flat.push(listunflat[key]);
    });
    return data_flat.flat();
};

const getaccountlist = async () => {
    aws.config.update({ region: 'us-east-1' });
    const org = new aws.Organizations();

    const getPaginatedResults = async (fn) => {
        const EMPTY = Symbol("empty");
        const res = [];
        for await (const lf of (async function* () {
            let NextMarker = EMPTY;
            while (NextMarker || NextMarker === EMPTY) {
                const { marker, results } = await fn(NextMarker !== EMPTY ? NextMarker : undefined);

                yield* results;
                NextMarker = marker;
            }
        })()) {
            res.push(lf);
        }

        return res;
    };

    const accounts = await getPaginatedResults(async (NextMarker) => {
        const functions = await org.listAccounts({ NextToken: NextMarker }).promise();
        return {
            marker: functions.NextToken,
            results: functions.Accounts,
        };
    });

    let account_list = []
    for (let index = 0; index < accounts.length; index++) {
        account_list.push({ "account_name": accounts[index].Name, "Account_id": accounts[index].Id });
    }
    return await account_list;
};

const getStream = () => {
    let readStream = fs.createReadStream(RawFileName, 'utf8');\
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
            result[account_id].push({ "type": type, "quantity": 0, "date": today, "account_id": account_id, "Account_name": account_name })
        };

        // Make the variable easier to access
        count_type = result[account_id].find(v => v.type === type)
        try {
            //If exist increment quantity
            count_type.quantity === 'number'
            count_type.quantity = count_type.quantity + 1 || 1
        } catch (error) {
            // Else we init the new type at one this time because the increment passed
            result[account_id].push({ "type": type, "quantity": 1, "date": today, "account_id": account_id, "Account_name": account_name })
        }
    });
})

getStream().on('end', function () {
    // Writing the csv file locally
    sleep(10000).then(() => {
        const createCsvWriter = csvwriter.createObjectCsvWriter;
        const csvWriter = createCsvWriter({
            path: CSVFilePath,
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
            console.log('file written')
        });
    })
})
