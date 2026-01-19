{-# LANGUAGE OverloadedStrings #-}

module Routes where

import           Control.Monad                 (unless, when)
import           Control.Monad.Trans.Class     (lift)
import           Control.Monad.Trans.Maybe
import qualified Crypto.BCrypt                 as BCrypt
import           Data.Aeson                    (object, (.=))
import qualified Data.ByteString.Lazy          as LBS
import           Data.Pool
import qualified Data.Text                     as T
import qualified Data.Text.Encoding            as DE
import qualified Data.Text.Lazy                as TL
import           Database.PostgreSQL.Simple
import           Network.HTTP.Types.Status
import qualified Web.ClientSession             as CS
import           Web.Scotty

import           Database
import           Session
import           Types
import           Views


-- Controllers
homepageController :: CS.Key -> Pool Connection -> ActionM ()
homepageController key pool = do
  maybeSession <- getSession key
  blogs <- case maybeSession of
    Nothing -> liftIO $ withResource pool getPublicBlogs
    Just session -> liftIO $ withResource pool $ \conn ->
      getUserAccessibleBlogs conn (sessionUserId session)
  html $ homepageHtml maybeSession blogs

viewNewBlogController :: CS.Key -> ActionM ()
viewNewBlogController key = do
  maybeSession <- getSession key
  html $ newBlogHtml maybeSession

blogPostController :: CS.Key -> Pool Connection -> ActionM ()
blogPostController key pool = do
  maybeSession <- getSession key
  btitle <- formParam "title"
  bcontent <- formParam "content"
  isPublicParam <- formParamMaybe "public"
  let ispublic = maybe False (not . T.null) isPublicParam
  case maybeSession of
    Nothing -> do
      status status401
      html $ newBlogHtml Nothing
    Just session -> do
      maybeBlogId <- liftIO $ withResource pool $ \conn ->
        createBlog conn (sessionUserId session) btitle bcontent ispublic
      case maybeBlogId of
        Nothing         -> redirect "/"
        Just currBlogId -> redirect ("/blog/" <> (TL.pack $ show currBlogId))

loginController :: CS.Key -> Pool Connection -> ActionM ()
loginController key pool = do
  result <- runMaybeT $ do
    uname <- lift $ formParam "username"
    pwd <- lift $ formParam "password"
    user <- MaybeT . liftIO $
      withResource pool $ \conn -> getUserByUsername conn uname

    let validPassword = BCrypt.validatePassword (DE.encodeUtf8 $ passwordHash user) (DE.encodeUtf8 pwd)

    unless validPassword $ MaybeT (return Nothing)

    return user

  case result of
    Nothing -> do
      status status401
      html $ loginPageHtml True

    Just user -> do
      let sessionData = SessionData (userId user) (username user) (isAdmin user)
      setSessionCookie key sessionData
      redirect "/"


registerController :: CS.Key -> Pool Connection -> ActionM ()
registerController key pool = do
  result <- runMaybeT $ do
    uname <- lift $ formParam "username"
    pwd <- lift $ formParam "password"

    when (length pwd < 4) $ MaybeT (return Nothing)

    phash <- MaybeT . liftIO $
      BCrypt.hashPasswordUsingPolicy
        BCrypt.slowerBcryptHashingPolicy
        (DE.encodeUtf8 $ T.pack pwd)

    uid <- MaybeT . liftIO $
      withResource pool $ \conn ->
        createUser conn uname False phash

    return (uname, uid)

  case result of
    Nothing -> do
      status status401
      html $ registerPageHtml True

    Just (uname, uid) -> do
      let sessionData = SessionData uid uname False -- Non-admin by default
      setSessionCookie key sessionData
      redirect "/"

logoutController :: ActionM ()
logoutController = do
  clearSessionCookie
  redirect "/"

blogViewController :: CS.Key -> Pool Connection -> ActionM ()
blogViewController key pool = do
  bid <- pathParam "id"
  maybeSession <- getSession key
  maybeBlog <- liftIO $ withResource pool $ \conn -> getBlogById conn bid

  case maybeBlog of
    Nothing -> do
      status status404
      html $ blogNotFoundHtml maybeSession
    Just blog -> do
      canAccess <- case maybeSession of
        Nothing -> return $ bwaIsPublic blog
        Just session -> liftIO $ withResource pool $ \conn -> isBlogAvailable conn bid (sessionUserId session)

      if canAccess
        then html $ blogPageHtml maybeSession blog
        else do
          status status403
          html $ blogNotFoundHtml maybeSession


-- API
apiPublicBlogsController :: Pool Connection -> ActionM ()
apiPublicBlogsController pool = do
  blogs <- liftIO $ withResource pool getPublicBlogs
  json blogs

apiPublicUserList :: Pool Connection -> ActionM ()
apiPublicUserList pool = do
  users <- liftIO $ withResource pool getAllUsers
  json users

rssController :: Pool Connection -> ActionM ()
rssController pool = do
  blogs <- liftIO $ withResource pool getPublicBlogs
  setHeader "Content-Type" "application/rss+xml"
  raw $ LBS.fromStrict $ DE.encodeUtf8 $ T.pack $ unlines
    [ "<?xml version=\"1.0\" encoding=\"UTF-8\" ?>"
    , "<rss version=\"2.0\">"
    , "<channel>"
    , "<title>Blog Feed</title>"
    , "<description>Public blog posts</description>"
    , concatMap blogToRSS blogs
    , "</channel>"
    , "</rss>"
    ]
  where
    blogToRSS blog = unlines
      [ "<item>"
      , "<title>" ++ T.unpack (bwaTitle blog) ++ "</title>"
      , "<description>" ++ T.unpack (bwaContent blog) ++ "</description>"
      , "<pubDate>" ++ show (bwaCreatedAt blog) ++ "</pubDate>"
      , "</item>"
      ]

privateApiBlogController :: Pool Connection -> ActionM ()
privateApiBlogController pool = do
  bid <- pathParam "id"
  maybeBlog <- liftIO $ withResource pool $ \conn -> getBlogById conn bid

  case maybeBlog of
    Nothing -> do
      status status404
      json $ object ["error" .= ("Blog not found" :: String)]
    Just blog -> json blog

privateApiUserBlogsController :: Pool Connection -> ActionM ()
privateApiUserBlogsController pool = do
  uid <- pathParam "id"
  blogs <- liftIO $ withResource pool $ \conn -> getUserAccessibleBlogs conn uid
  json blogs

-- Setup routes
setupRoutes :: CS.Key -> Pool Connection -> ScottyM ()
setupRoutes key pool = do
  -- Public web interface
  get "/" $ homepageController key pool
  get "/login" $ html (loginPageHtml False)
  post "/login" $ loginController key pool
  get "/register" $ html (registerPageHtml False)
  post "/register" $ registerController key pool
  get "/logout" $ logoutController
  get "/blog/:id" $ blogViewController key pool
  get "/new_blog" $ viewNewBlogController key
  post "/new_blog" $ blogPostController key pool

  -- Public API
  get "/api/blogs" $ apiPublicBlogsController pool
  get "/api/users" $ apiPublicUserList pool
  get "/rss" $ rssController pool

setupPrivateRoutes :: CS.Key -> Pool Connection -> ScottyM ()
setupPrivateRoutes key pool = do
  -- Private API
  get "/private-api/blogs/:id" $ privateApiBlogController pool
  get "/private-api/user/:id/blogs" $ privateApiUserBlogsController pool
