{-# LANGUAGE DeriveGeneric     #-}
{-# LANGUAGE OverloadedStrings #-}

module Types where

import           Data.Aeson
import           Data.Text                          (Text)
import           Data.Time                          (UTCTime)
import           Database.PostgreSQL.Simple.FromRow
import           GHC.Generics

-- User data type
data User = User
  { userId       :: Int
  , username     :: Text
  , isAdmin      :: Bool
  , passwordHash :: Text
  , uCreatedAt   :: UTCTime
  } deriving (Show, Generic)

instance FromRow User where
  fromRow = User <$> field <*> field <*> field <*> field <*> field

instance ToJSON User where
  toJSON user = object
    [ "id" .= userId user
    , "username" .= username user
    , "isAdmin" .= isAdmin user
    , "createdAt" .= uCreatedAt user
    ] -- Skip password hash


-- Blog post data type
data Blog = Blog
  { blogId    :: Int
  , authorId  :: Int
  , blogTitle :: Text
  , content   :: Text
  , isPublic  :: Bool
  , createdAt :: UTCTime
  } deriving (Show, Generic)

instance FromRow Blog where
  fromRow = Blog <$> field <*> field <*> field <*> field <*> field <*> field

instance ToJSON Blog where
  toJSON blog = object
    [ "id" .= blogId blog
    , "authorId" .= authorId blog
    , "blogTitle" .= blogTitle blog
    , "content" .= content blog
    , "isPublic" .= isPublic blog
    , "createdAt" .= createdAt blog
    ]

-- Blog with author name (for display)
data BlogWithAuthor = BlogWithAuthor
  { bwaId         :: Int
  , bwaAuthorId   :: Int
  , bwaAuthorName :: Text
  , bwaTitle      :: Text
  , bwaContent    :: Text
  , bwaIsPublic   :: Bool
  , bwaCreatedAt  :: UTCTime
  } deriving (Show)

instance FromRow BlogWithAuthor where
  fromRow = BlogWithAuthor <$> field <*> field <*> field <*> field
                           <*> field <*> field <*> field

instance ToJSON BlogWithAuthor where
  toJSON blog = object
    [ "id" .= bwaId blog
    , "authorId" .= bwaAuthorId blog
    , "authorName" .= bwaAuthorName blog
    , "title" .= bwaTitle blog
    , "content" .= bwaContent blog
    , "isPublic" .= bwaIsPublic blog
    , "createdAt" .= bwaCreatedAt blog
    ]

-- Request types
data LoginRequest = LoginRequest
  { loginUsername :: Text
  , loginPassword :: Text
  } deriving (Show, Generic)

instance FromJSON LoginRequest

data CreateBlogRequest = CreateBlogRequest
  { createTitle        :: Text
  , createContent      :: Text
  , createIsPublic     :: Bool
  } deriving (Show, Generic)

instance FromJSON CreateBlogRequest
