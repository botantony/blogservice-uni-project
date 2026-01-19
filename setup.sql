CREATE DATABASE blogdb;
CREATE USER bloguser WITH PASSWORD 'blogpass';
GRANT ALL PRIVILEGES ON DATABASE blogdb TO bloguser;
\c blogdb
GRANT ALL ON SCHEMA public TO bloguser;
