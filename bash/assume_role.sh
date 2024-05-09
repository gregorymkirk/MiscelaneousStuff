# you need to call this with source, not run it directly
# jq is a prerequisite for this to work
ROLE=sre_r
ARN=$(aws sts get-caller-identity --query "Arn" --output text)
ROOT=${ARN%:*}
USER=${ARN##**/}
 
CREDENTIALS=$(aws sts assume-role --role-arn $ROOT:role/$ROLE --role-session-name $USER)
export AWS_ACCESS_KEY_ID=$(echo $CREDENTIALS|jq ".Credentials.AccessKeyId" -r)
export AWS_SECRET_ACCESS_KEY=$(echo $CREDENTIALS|jq ".Credentials.SecretAccessKey" -r)
export AWS_SESSION_TOKEN=$(echo $CREDENTIALS|jq ".Credentials.SessionToken" -r)
EXPIRY=$(echo $CREDENTIALS|jq ".Credentials.Expiration" -r)
echo "Your credentials expire at $EXPIRY"
 
aws sts get-caller-identity