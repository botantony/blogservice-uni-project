## Setup project

```bash
# Optional steps: create virtual machine
## 1. Install a virtual machine. I use lima: https://github.com/lima-vm/lima
##    It is a very convenient Linux VM launcher designed for macOS. It also has great
##    Linux support.
brew install lima

## You may need to install QEMU if you use Linux/plan to emulate another architecture
brew install qemu

## 2. Create virtual machine using provided template
## You may need to adjust mount location and VM architecture
limactl create --name=blogservice-vm ./lima-config.yaml

## 3. Open VM's shell
limactl start blogservice-vm
limactl shell blogservice-vm

# 1. Create `.env` file and fill the secrets
cp .env.example .env

# 2. Run bootstrap script
sudo ./bootstrap.sh

# Note that I changed default port used by PosgreSQL (because I have another PosgreSQL instance running in Docker)
# You may need to change default port in config

## 1. Check major PostgreSQL version
psql --version

## 2. Add the line to the config
## It was 17 in my case
export PSQL_VERSION="17"

## Change `port` field in this file
sudo vi "/etc/postgresql/${PSQL_VERSION}/main/postgresql.conf"
sudo systemctl restart postgresql

# 3. Now we need to setup the database
sudo -u postgres psql -f ./setup.sql

# 4. Build project using Stack as `bloguser`. Stack will install local GHC & Cabal automatically
sudo -u bloguser bash
stack install --local-bin-path bin

# 5. Start the service:
sudo systemd start blog-service
sudo systemd enable blog-service

# Now you should be able to open a https://localhost:5555 and use the website
```

Some stuff for testing:
1. Generating password hash:
```haskell
-- stack repl
import qualified Crypto.BCrypt as BCrypt
import qualified Data.Text.Encoding as E
import qualified Data.Text as T
let myPassword = "your_password"
BCrypt.hashPasswordUsingPolicy BCrypt.slowerBcryptHashingPolicy (E.encodeUtf8 $ T.pack myPassword)
```
2. Inserting sample data into the database:
```sql
-- sudo -u postgres psql
\c blogdb
INSERT INTO users (username, is_admin, password_hash) VALUES
('user1', true, '$2y$14$.gy6.CYaa/SftXPRqL3xmO50fTlibCLoeCmjBPEyVERl2kSReQISW'), -- `qwerty123`
('user2', false, '$2y$14$.gy6.CYaa/SftXPRqL3xmO50fTlibCLoeCmjBPEyVERl2kSReQISW');

INSERT INTO blogs (author_id, title, content, is_public) VALUES
(1, 'First blog', 'Foo bar', true),
(1, 'Private Blog', 'My secret: I love pancakes', false),
(2, 'Second blog', 'Second blog of a second user', true);
```
