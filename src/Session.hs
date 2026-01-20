{-# LANGUAGE OverloadedStrings #-}

module Session where

import           Control.Monad             (join)
import           Control.Monad.Trans.Class (lift)
import           Control.Monad.Trans.Maybe
import qualified Data.ByteString           as BS
import qualified Data.ByteString.Base64    as B64
import qualified Data.Text                 as T
import qualified Data.Text.Encoding        as TE
import qualified Data.Text.Lazy            as TL
import           Data.Time.Clock           (addUTCTime, getCurrentTime)
import           Network.HTTP.Types.Status
import qualified Web.ClientSession         as CS
import           Web.Cookie
import           Web.Scotty


data SessionData = SessionData
  { sessionUserId   :: Int
  , sessionUsername :: T.Text
  , sessionIsAdmin  :: Bool
  } deriving (Show)

-- Helper function
rightToMaybe :: Either a b -> Maybe b
rightToMaybe (Right x) = Just x
rightToMaybe _         = Nothing

sessionCookieName :: BS.ByteString
sessionCookieName = "blog_session"

encodeSession :: SessionData -> T.Text
encodeSession (SessionData uid uname uadmin) = T.pack (show uid) <> ":" <> uname <> ":" <> T.pack (show uadmin)

decodeSession :: T.Text -> Maybe SessionData
decodeSession txt = case T.splitOn ":" txt of
  [uidStr, uname, uadminStr] -> case (reads (T.unpack uidStr), reads (T.unpack uadminStr)) of
    ([(uid, "")], [(uadmin, "")]) -> Just $ SessionData uid uname uadmin
    _                             -> Nothing
  _ -> Nothing

createSessionCookie :: CS.Key -> SessionData -> IO SetCookie
createSessionCookie key sessionData = do
  currentTime <- getCurrentTime
  let sessionText = encodeSession sessionData
      oneDay      = 24 * 3600
      expiryTime  = addUTCTime oneDay currentTime
  encrypted   <- CS.encryptIO key (TE.encodeUtf8 sessionText)

  return $ def
    { setCookieName     = sessionCookieName
    , setCookieValue    = B64.encode encrypted
    , setCookiePath     = Just "/"
    , setCookieExpires  = Just expiryTime
    , setCookieHttpOnly = True
    , setCookieSecure   = False
    , setCookieSameSite = Just sameSiteLax
    }

setSessionCookie :: CS.Key -> SessionData -> ActionM ()
setSessionCookie key sessionData = do
  cookie <- liftIO $ createSessionCookie key sessionData
  setHeader "Set-Cookie" (TL.fromStrict $ TE.decodeUtf8 $ renderSetCookieBS cookie)

getSession :: CS.Key -> ActionM (Maybe SessionData)
getSession key = do
  result <- runMaybeT $ do
    cookieHeader <- lift $ header "Cookie"
    cookieText <- hoistMaybe cookieHeader

    let cookies = parseCookies $ TE.encodeUtf8 $ TL.toStrict cookieText

    sessionCookie <- hoistMaybe $ lookup sessionCookieName cookies
    encrypted <- hoistMaybe . rightToMaybe $ B64.decode sessionCookie

    let decrypted = CS.decrypt key encrypted

    return $ decrypted >>= (decodeSession . TE.decodeUtf8)

  return $ join result

clearSessionCookie :: ActionM ()
clearSessionCookie = do
  currentTime <- liftIO getCurrentTime
  let expiredCookie = def
        { setCookieName = sessionCookieName
        , setCookieValue = ""
        , setCookiePath = Just "/"
        , setCookieExpires = Just $ addUTCTime (-3600) currentTime
        , setCookieHttpOnly = True
        }
  setHeader "Set-Cookie" (TL.fromStrict $ TE.decodeUtf8 $ renderSetCookieBS expiredCookie)

requireAuth :: CS.Key -> (SessionData -> ActionM ()) -> ActionM ()
requireAuth key action = do
  maybeSession <- getSession key
  case maybeSession of
    Just sessionData -> action sessionData
    Nothing -> do
      setHeader "Location" "/login"
      status status302
