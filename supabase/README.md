# Supabase Database Project for Skolist

## 1. Introduction

This repository contains the Supabase database project for Skolist. It includes the necessary SQL files to create and populate the database with the required data.

## 2. Steps to run supabase locally

### 2.1 Downloading supabase cli

Follow the instructions on the [Supabase CLI](https://supabase.com/docs/guides/local-development/cli/getting-started) to download and install the Supabase CLI.

### 2.2 Running supabase locally

Run the following command to start the supabase local development setup:

```bash
supabase start
```

This will start the supabase local development setup and provide with you with the urls for different supabase services and relavant api keys

### 2.3 Feeding the seed into the database

- By default if you have the data in the seed.sql file, it will be fed into the database after doing `supabase start`
- If not done, or if you want to feed the seed into the database again, you can do so by running the following command:

```bash
supabase db reset
```

- In migrations folder, there are different sql files which are run in order to create the database schema and populate it with the required data. You can add another sql file to the migrations folder to add new tables or populate the existing tables with new data.
- In seeds folder, there are different sql files which are run in order to populate the database with the required data. You can add another sql file to the seeds folder to populate the existing tables with new data.
- But if you add newer data in seeds folder, you need to move that into the main seed.sql file via the command

```bash
cat supabase/seeds/*.sql > supabase/seed.sql
```

- Try to avoid editing the seed.sql file directly or pushing content to remote repo from this file

### 2.4 Stopping supabase locally

Run the following command to stop the supabase local development setup:

```bash
supabase stop
```