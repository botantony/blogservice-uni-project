{-# LANGUAGE DeriveGeneric     #-}
{-# LANGUAGE OverloadedStrings #-}

module Database where

import qualified Data.ByteString            as BS
import           Data.Pool                  as DP
import           Data.Text                  (Text)
import qualified Data.Text                  as T
import qualified Data.Text.Encoding         as DE
import           Database.PostgreSQL.Simple
import           GHC.Generics
import           System.Envy
import           Types

data DBConfig = DBConfig
  { dbHost     :: String
  , dbPort     :: Int
  , dbName     :: String
  , dbUser     :: String
  , dbPassword :: String
  } deriving (Generic, Show)

instance FromEnv DBConfig where
  fromEnv _ =
    DBConfig <$> envMaybe "DB_HOST" .!= "localhost"
             <*> envMaybe "DB_PORT" .!= 6543
             <*> env "DB_NAME"
             <*> env "DB_USER"
             <*> env "DB_PASSWORD"

-- Connection string from config
buildConnInfo :: DBConfig -> ConnectInfo
buildConnInfo cfg = ConnectInfo
  { connectHost = dbHost cfg
  , connectPort = fromIntegral $ dbPort cfg
  , connectUser = dbUser cfg
  , connectPassword = dbPassword cfg
  , connectDatabase = dbName cfg
  }

-- Database connection pool
createPool :: IO (Pool Connection)
createPool = do
  result <- decodeEnv :: IO (Either String DBConfig)
  case result of
    Left err -> error $ "Failed to load database config: " ++ err
    Right cfg -> do
    -- Magic numbers, took it from
    -- https://gist.github.com/221V/1ed6a69ee7e1669ce9e2d004d7089969#file-main-hs-L69-L83
      DP.newPool $ DP.defaultPoolConfig (connect $ buildConnInfo cfg) close 10.0 10

initDB :: Connection -> IO ()
initDB conn = do
  -- Using execute_ should be ok here as there is no user input
  -- For other need to use `query` function with `?` placeholder (`postgresql-simple` escapes strings)
  _ <- execute_ conn "CREATE TABLE IF NOT EXISTS users ( \
    \id SERIAL PRIMARY KEY, \
    \username VARCHAR(50) UNIQUE NOT NULL, \
    \is_admin BOOLEAN DEFAULT false, \
    \password_hash VARCHAR(255) NOT NULL, \
    \created_at TIMESTAMPTZ DEFAULT NOW() \
    \)"
  _ <- execute_ conn "CREATE TABLE IF NOT EXISTS blogs ( \
    \id SERIAL PRIMARY KEY, \
    \author_id INT REFERENCES users(id), \
    \title VARCHAR(255) NOT NULL, \
    \content TEXT NOT NULL, \
    \is_public BOOLEAN DEFAULT true, \
    \created_at TIMESTAMPTZ DEFAULT NOW() \
    \)"
  return ()


-- User operations
getUserByUsername :: Connection -> Text -> IO (Maybe User)
getUserByUsername conn uname = do
  results <- query conn
    "SELECT id, username, is_admin, password_hash, created_at FROM users WHERE username = ?"
    (Only uname)
  return $ case results of
    (user:_) -> Just user
    []       -> Nothing

createUser :: Connection -> Text -> Bool -> BS.ByteString -> IO (Maybe Int)
createUser conn uname uIsAdmin phash = do
  if T.null uname || T.length uname > 50
    then return Nothing
    else do
      results <- query conn
        "INSERT INTO users (username, is_admin, password_hash) VALUES (?, ?, ?) RETURNING id"
        (uname, uIsAdmin, DE.decodeLatin1 phash)
      return $ case results of
        (Only uid:_) -> Just uid
        []           -> Nothing

getAllUsers :: Connection -> IO [User]
getAllUsers conn =
  query_ conn
    "SELECT id, username, is_admin, password_hash, created_at FROM users ORDER BY id ASC"

getPublicBlogs :: Connection -> IO [BlogWithAuthor]
getPublicBlogs conn =
  query_ conn
    "SELECT b.id, b.author_id, u.username, b.title, b.content, b.is_public, b.created_at \
    \FROM blogs b JOIN users u ON b.author_id = u.id \
    \WHERE b.is_public = true \
    \ORDER BY b.created_at ASC LIMIT 100"

getBlogById :: Connection -> Int -> IO (Maybe BlogWithAuthor)
getBlogById conn bid = do
  results <- query conn
    "SELECT b.id, b.author_id, u.username, b.title, b.content, b.is_public, b.created_at \
    \FROM blogs b JOIN users u ON b.author_id = u.id \
    \WHERE b.id = ?"
    (Only bid)
  return $ case results of
    (blog:_) -> Just blog
    []       -> Nothing

createBlog :: Connection -> Int -> Text -> Text -> Bool -> IO (Maybe Int)
createBlog conn aid btitle bcontent ispublic = do
  if T.null btitle || T.length btitle > 255
    then return Nothing
    else if T.null bcontent || T.length bcontent > 10000
      then return Nothing
      else do
        results <- query conn
          "INSERT INTO blogs (author_id, title, content, is_public) \
          \VALUES (?, ?, ?, ?) RETURNING id"
          (aid, btitle, bcontent, ispublic)
        return $ case results of
          (Only bid:_) -> Just bid
          []           -> Nothing

isBlogAvailable :: Connection -> Int -> Int -> IO Bool
isBlogAvailable conn bid uid = do
  results <- query conn
    "SELECT EXISTS( \
    \  SELECT 1 FROM blogs b \
    \  JOIN users u ON u.id = ? \
    \  WHERE b.id = ? \
    \  AND (b.is_public = true OR b.author_id = ? OR u.is_admin = true) \
    \)"
    (uid, bid, uid) :: IO [Only Bool]

  return $ case results of
    (Only available:_) -> available
    []                 -> False

getUserAccessibleBlogs :: Connection -> Int -> IO [BlogWithAuthor]
getUserAccessibleBlogs conn uid =
  query conn
    "SELECT DISTINCT b.id, b.author_id, u.username, b.title, b.content, b.is_public, b.created_at \
    \FROM blogs b \
    \JOIN users u ON b.author_id = u.id \
    \WHERE b.is_public = true \
    \   OR b.author_id = ? \
    \   OR (SELECT is_admin FROM users WHERE id = ?) = true \
    \ORDER BY b.created_at DESC LIMIT 100"
    (uid, uid)
