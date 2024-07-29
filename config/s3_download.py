import sys
import boto3
from urllib.parse import urlparse

s3 = boto3.client('s3')

def copy_from_s3(target, dest):
    parsed = urlparse(target)

    bucket = parsed.netloc
    key = parsed.path.lstrip('/')

    print(f"downloading s3://{bucket}/{key} to {dest}")
    s3.download_file(bucket, key, dest)

if __name__ == "__main__":
    target = sys.argv[1]
    dest = sys.argv[2]

    if not target or not dest:
        raise ValueError("Missing args")
    
    copy_from_s3(target, dest)