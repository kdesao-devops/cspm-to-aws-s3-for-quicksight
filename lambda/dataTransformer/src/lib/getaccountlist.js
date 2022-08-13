const aws = require('aws-sdk');
const sts = new aws.STS();

const getCrossAccountCredentials = async () => {
    const timestamp = (new Date()).getTime();
    return new Promise((resolve, reject) => {
        const params = {
            RoleArn: process.env.ASSUMED_ROLE_ARN,
            RoleSessionName: `CSPM-Dashboard-Get-account-list-${timestamp}`
        };
        sts.assumeRole(params, (err, data) => {
            if (err) console.error(err);
            else {
                resolve({
                    accessKeyId: data.Credentials.AccessKeyId,
                    secretAccessKey: data.Credentials.SecretAccessKey,
                    sessionToken: data.Credentials.SessionToken,
                });
            }
        });
    });
}

const getaccountlist = async () => {
    aws.config.update({ region: 'us-east-1' });
    const accessparams = await getCrossAccountCredentials();
    const org = new aws.Organizations(accessparams);

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
}

module.exports.getaccountlist = getaccountlist;
