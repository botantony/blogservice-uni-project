{-# LANGUAGE OverloadedStrings #-}

module Main where

import qualified Data.Pool                            as DP
import           Network.Wai.Middleware.RequestLogger
import           System.FilePath                      ((</>))
import           System.IO                            (hPutStrLn, stderr)
import qualified Web.ClientSession                    as CS
import           Web.Scotty

import           Database
import           Routes

main :: IO ()
main = do
  hPutStrLn stderr "Starting blog service..."
  let keyFile = "config" </> CS.defaultKeyFile
  key <- CS.getKey keyFile
  pool <- createPool
  hPutStrLn stderr "Database connection pool created"
  DP.withResource pool initDB
  hPutStrLn stderr "Database initialized"
  hPutStrLn stderr "Starting web server on port 5555..."

  scotty 5555 $ do
    middleware logStdout
    setupRoutes key pool

  scotty 5556 $ do
    middleware logStdout
    setupPrivateRoutes key pool
