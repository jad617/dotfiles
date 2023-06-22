#!/usr/bin/env python3

###################
# Imports
###################

import argparse
import os

import hvac


###################
# Functions
###################
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


def destroy_secret(path: str):
    client.secrets.kv.v2.delete_metadata_and_all_versions(
        path=path,
    )


def recursive_fetch(project: str, vault_dest_path: str):
    if not project.endswith("/"):
        if not args.dryrun:
            # Fetch secret data
            secret_data = fetch_secret_data(project)
            # Write secret to destination
            write_secret_to_dest(secret_data, vault_dest_path)
        print(
            f"\nSecret from:        {project}\nhas been copied to: {vault_dest_path}")
    else:
        secrets = list_keys(project)

        for secret in secrets:
            if secret.endswith("/"):  # If folder,then continue
                recursive_fetch(project + secret, vault_dest_path)
            else:  # if secret, fetch secret data
                secret_current_path = project + secret

                # We need to have the secret path without the vault_default_path path
                secret_suffix = secret_current_path.replace(
                    vault_default_path, "")

                # If vault_default_path has "/" but not vault_dest_path we need to add "/"
                if not vault_dest_path.endswith("/"):
                    vault_dest_path = vault_dest_path + "/"

                # We need the full path of for the destination secret
                secret_dest_path = vault_dest_path + secret_suffix
                if not args.dryrun:
                    # Fetch secret data
                    secret_data = fetch_secret_data(secret_current_path)
                    # Write secret to destination
                    write_secret_to_dest(secret_data, secret_dest_path)

                print(
                    f"\nSecret from:        {secret_current_path}\nhas been copied to: {secret_dest_path}"
                )


def recursive_delete(project: str, vault_dest_path: str):
    secrets = list_keys(project)

    for secret in secrets:
        if secret.endswith("/"):  # If folder, then continue
            recursive_delete(project + secret, vault_dest_path)
        else:  # if secret, fetch secret data
            secret_current_path = project + secret
            if not args.dryrun:
                destroy_secret(secret_current_path)

            print(f"\nSecret path to DELETE:        {secret_current_path}")


###################
# Cli Args
###################
parser = argparse.ArgumentParser()

parser.add_argument("--source", type=str, required=True,
                    help="Vault full source path")

parser.add_argument(
    "--dest",
    type=str,
    required=False,
    help="Vault full destination path, copy everything under path specified by --source, if the path does not end with a '/' it will only copy the secret",
)

parser.add_argument(
    "--delete",
    default=False,
    action=argparse.BooleanOptionalAction,
    help="Delete everything under path specified by --source, if the path does not end with a '/' it will only delete the secret",
)

parser.add_argument(
    "--dryrun",
    default=False,
    action=argparse.BooleanOptionalAction,
    help="Allows you to preview without applying the changes",
)

args = parser.parse_args()

if not (args.dest or args.delete):
    parser.error(
        "You must at least use --dest or --delete in combination with --source"
    )

###################
# main()
###################
# Source Vault Path to fetch all the secrets from
vault_default_path = args.source

try:
    # Vault Client init
    client = hvac.Client(
        url=os.environ["VAULT_ADDR"],
        token=os.environ["VAULT_TOKEN"],
    )

    if args.delete:
        if args.dryrun:
            print("***Dry Run Started***")

        recursive_delete(args.source, args.dest)

        if args.dryrun:
            print(f"\n***Dry Run Ended***")
    else:
        if args.dryrun:
            print("***Dry Run Started***")

        recursive_fetch(args.source, args.dest)

        if args.dryrun:
            print(f"\n***Dry Run Ended***")
except KeyError as e:
    print("Unable to find VAULT_ADDR or VAULT_TOKEN ENV variable")

except hvac.exceptions.InvalidPath:
    print(f"Unable to find the path: secrets/{args.source}")
