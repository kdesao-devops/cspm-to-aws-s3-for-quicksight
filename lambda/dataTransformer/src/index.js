module.exports.index = async () => {
  console.log("This is a placeholder for the data transformer function");
  return {
    statusCode: 200,
    headers: {},
    body: {
      rawDataKey:
        "/rawData/cloud-guard-protected-assets-2022-July-21-044308.json",
      transformedDataKey:
        "/transformedData/cloud-guard-protected-assets-2022-July-21-044308.json",
    },
  };
};
