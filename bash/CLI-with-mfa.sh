# you need to call this with source, not run it directly
# jq is a prerequisite for this to work
TOKEN=arn:aws:iam::<ACCOUNTNUMBER>:mfa/<YOUR AWS USERNAME> # might neet toc hage this if in gov/china
AWS_ACCESS_KEY_ID=<YOUR ACCESS KEY ID>
AWS_SECRET_ACCESS_KEY=<YOUR SECRET ACCESS KEY>
 
# export AWS_DEFAULT_REGION=us-west-1  # Only needed if not using default auth domain.
# export AWS_CA_BUNDLE=~/.aws/certificate.cer 
echo "Enter MFA token value:"
read MFA
CREDENTIALS=$(aws sts get-session-token --serial-number $TOKEN --token-code $MFA )
 
export AWS_ACCESS_KEY_ID=$(echo $CREDENTIALS|jq ".Credentials.AccessKeyId" -r)
export AWS_SECRET_ACCESS_KEY=$(echo $CREDENTIALS|jq ".Credentials.SecretAccessKey" -r)
export AWS_SESSION_TOKEN=$(echo $CREDENTIALS|jq ".Credentials.SessionToken" -r)
EXPIRY=$(echo $CREDENTIALS|jq ".Credentials.Expiration" -r)
echo "Your credentials expire at $EXPIRY"
 
aws sts get-caller-identity