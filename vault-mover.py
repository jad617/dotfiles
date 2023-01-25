#!/usr/bin/env python3

import argparse
import os

import hvac


def list_keys(root_path: str) -> list:
    list_response = client.secrets.kv.v2.list_secrets(path=root_path)

    return list_response["data"]["keys"]


def fetch_secret_data(path: str) -> dict:
    secret_response = client.secrets.kv.v2.read_secret_version(
        path=path,
    )

    return secret_response["data"]["data"]


def write_secret_to_dest(secret_data: dict, dest_dir: str):
    client.secrets.kv.v2.create_or_update_secret(
        path=dest_dir,
        secret=secret_data,
    )


def recursive_fetch(project: str, vault_dest_project: str):
    secrets = list_keys(project)

    for secret in secrets:
        if secret.endswith("/"):  # If folder continue
            recursive_fetch(project + secret, vault_dest_project)
        else:  # if secret, fetch secret data
            secret_current_path = project + secret
            # Fetch secret data

            # We need to have the secret path without the vault_current_project path
            secret_suffix = secret_current_path.replace(
                vault_current_project, "")

            # We need the full path of for the destination secret
            secret_dest_path = vault_dest_project + secret_suffix
            if not args.dryrun:
                # Fetch secret data
                secret_data = fetch_secret_data(secret_current_path)
                # Write secret to destination
                write_secret_to_dest(secret_data, secret_dest_path)

            print(
                f"\nSecret from:        {secret_current_path}\nhas been copied to: {secret_dest_path}"
            )


###################
# main()
###################

# Cli Args
parser = argparse.ArgumentParser()

parser.add_argument(
    "--source", "-s", type=str, required=True, help="Vault full source path"
)
parser.add_argument(
    "--dest", "-d", type=str, required=True, help="Vault full destination path"
)
parser.add_argument("--dryrun", default=False,
                    action=argparse.BooleanOptionalAction)
args = parser.parse_args()

# Source Vault Path to fetch all the secrets from
vault_current_project = args.source

try:
    # Vault Client init
    client = hvac.Client(
        url=os.environ["VAULT_ADDR"],
        token=os.environ["VAULT_TOKEN"],
    )

    # for project in vault_projects:
    # recursive_fetch(vault_current_project, vault_dest_project)
    if args.dryrun:
        print("***Dry Run Started***")
        recursive_fetch(args.source, args.dest)
        print(f"\n***Dry Run Ended***")
    else:
        recursive_fetch(args.source, args.dest)
except KeyError as e:
    print("Unable to find VAULT_ADDR or VAULT_TOKEN ENV variable")
