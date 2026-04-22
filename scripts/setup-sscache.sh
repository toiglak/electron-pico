set -e

# Set names
RG_NAME="electron-pico-cache-rg-$(date +%s)"
STORAGE_ACCOUNT="elpico$(date +%s)"
CONTAINER_NAME="sccache"
LOCATION="polandcentral"

echo "Creating Resource Group..."
az group create --name $RG_NAME --location $LOCATION

echo "Creating Storage Account: $STORAGE_ACCOUNT..."
az storage account create \
    --name $STORAGE_ACCOUNT \
    --resource-group $RG_NAME \
    --location $LOCATION \
    --sku Standard_LRS \
    --kind StorageV2 \
    --require-infrastructure-encryption false

echo "Creating Blob Container..."
az storage container create \
    --name $CONTAINER_NAME \
    --account-name $STORAGE_ACCOUNT \
    --auth-mode key

echo "--- SUCCESS ---"
echo "AZURE_STORAGE_ACCOUNT: $STORAGE_ACCOUNT"
echo "AZURE_STORAGE_CONTAINER: $CONTAINER_NAME"
echo "AZURE_STORAGE_KEY:"
az storage account keys list \
    --account-name $STORAGE_ACCOUNT \
    --query "[0].value" -o tsv
