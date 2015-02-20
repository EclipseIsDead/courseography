{-# LANGUAGE OverloadedStrings, FlexibleContexts, GADTs, ScopedTypeVariables #-}
module SVGBuilder where

import SVGTypes
import Tables
import Control.Monad.IO.Class  (liftIO)
import qualified Data.Conduit.List as CL
import Database.Persist
import Database.Persist.Sqlite
import Data.Char
import Data.Conduit
import Data.List.Split
import Data.List
import JsonParser
import ParserUtil

-- | Builds a Rect from a database entry in the rects table.
buildRect :: [Text] -> Rects -> Shape
buildRect texts entity = do
    let rectTexts = filter (\x -> intersects
                            (fromRational (rectsWidth entity))
                            (fromRational (rectsHeight entity))
                            (fromRational (rectsXPos entity))
                            (fromRational (rectsYPos entity))
                            9
                            (fromRational (textXPos x))
                            (fromRational (textYPos x))
                            ) texts
    let textString = concat $ map textText rectTexts
    let id_ = (if rectsIsHybrid entity then "h" else "") ++ 
              (if isDigit $ head textString then "CSC" else "") ++ dropSlash textString
    Shape id_
          (rectsXPos entity)
          (rectsYPos entity)
          (rectsWidth entity)
          (rectsHeight entity)
          (rectsFill entity)
          (rectsStroke entity)
          rectTexts
          (rectsIsHybrid entity)
          9

-- | Determines the source and target nodes of the path.
buildPath :: [Shape] -> [Shape] -> Paths -> Int -> Path
buildPath rects ellipses entity idCounter =
    let coords = map point $ pathsD entity in
    if pathsIsRegion entity then
        Path ('p' : show idCounter)
             coords
             (pathsFill entity)
             (pathsFillOpacity entity)
             (pathsStroke entity)
             (pathsIsRegion entity)
             ""
             ""
    else
    let xStart = fromRational $ fst $ head coords
        yStart = fromRational $ snd $ head coords
        xEnd = fromRational $ fst $ last coords
        yEnd = fromRational $ snd $ last coords
        intersectingSourceRect = getIntersectingShape xStart yStart rects
        intersectingTargetRect = getIntersectingShape xEnd yEnd rects
        intersectingSourceBool = getIntersectingShape xStart yStart ellipses
        intersectingTargetBool = getIntersectingShape xEnd yEnd ellipses
        sourceNode = if null intersectingSourceRect then intersectingSourceBool else intersectingSourceRect
        targetNode = if null intersectingTargetRect then intersectingTargetBool else intersectingTargetRect in
        Path ('p' : show idCounter)
             coords
             (pathsFill entity)
             (pathsFillOpacity entity)
             (pathsStroke entity)
             (pathsIsRegion entity)
             sourceNode
             targetNode

-- | Gets the first rect that intersects with the given coordinates.
getIntersectingShape :: Float -> Float -> [Shape] -> String
getIntersectingShape xpos ypos shapes = do
    let intersectingShapes = filter (intersectsWithPoint xpos ypos) shapes
    if null intersectingShapes
    then ""
    else shapeId $ head intersectingShapes

-- | Determines if a rect intersects with the given coordinates.
intersectsWithPoint :: Float -> Float -> Shape -> Bool
intersectsWithPoint xpos ypos shape =
    intersects (fromRational $ shapeWidth shape)
               (fromRational $ shapeHeight shape)
               (fromRational $ shapeXPos shape)
               (fromRational $ shapeYPos shape)
               (shapeTolerance shape)
               xpos
               ypos

-- | Prints the database table 'rects'.
printDB :: IO ()
printDB = runSqlite dbStr $ do
              let sql = "SELECT * FROM rects"
              rawQuery sql [] $$ CL.mapM_ (liftIO . print)

-- | Builds a Text from a database entry in the texts table.
buildText :: Texts -> Text
buildText entity = 
    Text (textsXPos entity)
         (textsYPos entity)
         (textsText entity)
         (textsFontSize entity)
         (textsFontWeight entity)
         (textsFontFamily entity)

-- | Builds a Path from a database entry in the paths table.
buildEllipses :: [Text] -> Int -> [Ellipses] -> [Shape]
buildEllipses _ _ [] = []
buildEllipses texts idCounter entities = do
    let entity = head entities
    let ellipseText = filter (\x -> 
                                  intersects
                                  5
                                  5
                                  (fromRational (ellipsesXPos entity))
                                  (fromRational (ellipsesYPos entity))
                                  9
                                  (fromRational (textXPos x))
                                  (fromRational (textYPos x))
                                  ) texts
    Shape ("bool" ++ show idCounter)
            (ellipsesXPos entity)
            (ellipsesYPos entity)
            ((ellipsesRx entity) * 2)
            ((ellipsesRy entity) * 2)
            ""
            (ellipsesStroke entity)
            ellipseText
            False
            20 : buildEllipses texts (idCounter + 1) (tail entities)

-- | Rebuilds a path's `d` attribute based on a list of Rational tuples.
buildPathString :: [(Rational, Rational)] -> String
buildPathString d = unwords $ map (joinPathTuple . convertRationalTupToString) d

-- | Joins two String values in a tuple with a comma.
joinPathTuple :: (String, String) -> String
joinPathTuple tup = fst tup ++ "," ++ snd tup

-- | Converts a tuple of Rationals to a tuple of String.
convertRationalTupToString :: (Rational, Rational) -> (String, String)
convertRationalTupToString tup = (show $ fromRational (fst tup), show $ fromRational (snd tup))