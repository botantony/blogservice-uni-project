{-# LANGUAGE OverloadedStrings #-}

module Views where

import qualified Data.Text                     as T
import qualified Data.Text.Lazy                as TL
import           Text.Blaze.Html.Renderer.Text (renderHtml)
import qualified Text.Blaze.Html5              as H
import           Text.Blaze.Html5              ((!))
import qualified Text.Blaze.Html5.Attributes   as A

import           Session
import           Types


renderPage :: Maybe SessionData -> H.Html -> TL.Text
renderPage maybeSession cont = renderHtml $ H.docTypeHtml $ do
  H.head $ do
    H.title "Blog Service"
  H.body $ do
    H.div ! A.style "background: #f0f0f0; padding: 10px; margin-bottom: 20px;" $ do
      case maybeSession of
        Nothing -> do
          H.a ! A.href "/login" $ "Login"
          " | "
          H.a ! A.href "/register" $ "Register"
          " | "
          H.a ! A.href "/" $ "Home"
        Just session -> do
          "Logged in as " >> H.strong (H.toHtml $ sessionUsername session)
          " | "
          H.a ! A.href "/" $ "Home"
          " | "
          H.a ! A.href "/new_blog" $ "New blog"
          " | "
          H.a ! A.href "/logout" $ "Logout"
      " | "
      H.a ! A.href "/api/blogs" $ "API"
      " | "
      H.a ! A.href "/rss" $ "RSS"
    cont

homepageHtml :: Maybe SessionData -> [BlogWithAuthor] -> TL.Text
homepageHtml maybeSession blogs = renderPage maybeSession $ do
  H.h1 "Blog Feed"
  H.p $ do
    H.a ! A.href "/api/blogs" $ "API"
    " | "
    H.a ! A.href "/rss" $ "RSS"
  H.hr
  if null blogs
    then H.p "No blogs available."
    else mapM_ renderBlogItem blogs
  where
    renderBlogItem blog = H.div $ do
      H.h2 $ H.toHtml (bwaTitle blog)
      H.p $ do
        "by " >> H.strong (H.toHtml $ bwaAuthorName blog)
        " on " >> H.toHtml (show $ bwaCreatedAt blog)
        if bwaIsPublic blog
          then ""
          else " " >> H.em "[Private]"
      H.p $ H.toHtml (bwaContent blog)
      H.p $ H.a ! A.href (H.toValue $ "/blog/" <> T.pack (show $ bwaId blog)) $ "Read more"
      H.hr

userForm :: T.Text -> T.Text -> T.Text -> Bool -> H.Html
userForm header_ apiRoute failedText failed = do
  H.h1 (H.toHtml header_)
  if failed
    then H.p (H.toHtml failedText)
    else ""
  H.form ! A.method "POST" ! A.action (H.toValue apiRoute) $ do
    H.label "Username: "
    H.input ! A.type_ "text" ! A.name "username" ! A.maxlength "50"
    H.br
    H.label "Password: "
    H.input ! A.type_ "password" ! A.name "password"
    H.br
    H.button ! A.type_ "submit" $ (H.toHtml header_)

loginPageHtml :: Bool -> TL.Text
loginPageHtml = renderPage Nothing . userForm "Login" "/login" "Invalid login or password. Please try again"

registerPageHtml :: Bool -> TL.Text
registerPageHtml = renderPage Nothing . userForm "Register" "/register" "Registration failed. Please try again"

blogPageHtml :: Maybe SessionData -> BlogWithAuthor -> TL.Text
blogPageHtml maybeSession blog = renderPage maybeSession $ do
  H.h1 $ H.toHtml (bwaTitle blog)
  H.p $ do
    "by " >> H.strong (H.toHtml $ bwaAuthorName blog)
    " on " >> H.toHtml (show $ bwaCreatedAt blog)
    if bwaIsPublic blog
      then ""
      else " " >> H.em "[Private]"
  H.p $ H.toHtml (bwaContent blog)
  H.hr
  H.a ! A.href "/" $ "Back to feed"

blogNotFoundHtml :: Maybe SessionData -> TL.Text
blogNotFoundHtml maybeSession = renderPage maybeSession $ do
  H.h1 "Not found"
  H.a ! A.href "/" $ "Back to feed"

newBlogHtml :: Maybe SessionData -> TL.Text
newBlogHtml maybeSession = renderPage maybeSession $ do
  case maybeSession of
    Nothing -> do
      H.h1 "You need to login to be able to make blog posts!"
    _ -> do
      H.h1 "New blog post"
      H.form ! A.method "POST" ! A.action "/new_blog" $ do
        H.label "Title: "
        H.br
        H.input ! A.type_ "text" ! A.name "title" ! A.maxlength "255"
        H.br
        H.label "Content: "
        H.br
        H.textarea ! A.name "content" $ ""
        H.br
        H.label "Public: "
        H.input ! A.type_ "checkbox" ! A.name "public" ! A.checked ""
        H.br
        H.button ! A.type_ "submit" $ "Publish"
