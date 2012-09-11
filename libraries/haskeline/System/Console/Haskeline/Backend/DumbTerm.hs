module System.Console.Haskeline.Backend.DumbTerm where

import System.Console.Haskeline.Backend.Posix
import System.Console.Haskeline.Term
import System.Console.Haskeline.LineState
import System.Console.Haskeline.Monads as Monads

import System.IO
import qualified Data.ByteString as B

-- TODO: 
---- Put "<" and ">" at end of term if scrolls off.
---- Have a margin at the ends

data Window = Window {pos :: Int -- ^ # of visible chars to left of cursor
                }

initWindow :: Window
initWindow = Window {pos=0}

newtype DumbTerm m a = DumbTerm {unDumbTerm :: StateT Window (PosixT m) a}
                deriving (Monad, MonadIO, MonadException,
                          MonadState Window,
                          MonadReader Handle, MonadReader Encoders)

instance MonadReader Layout m => MonadReader Layout (DumbTerm m) where
    ask = lift ask
    local r = DumbTerm . local r . unDumbTerm

instance MonadTrans DumbTerm where
    lift = DumbTerm . lift . lift . lift

runDumbTerm :: IO RunTerm
runDumbTerm = posixRunTerm $ \enc h ->
                TermOps {
                        getLayout = tryGetLayouts (posixLayouts h),
                        runTerm = \f -> 
                                runPosixT enc h $ evalStateT' initWindow
                                $ unDumbTerm
                                $ withPosixGetEvent enc [] f
                        }
                                
instance (MonadException m, MonadLayout m) => Term (DumbTerm m) where
    reposition _ s = refitLine s
    drawLineDiff = drawLineDiff'
    
    printLines = mapM_ (\s -> printText (s ++ crlf))
    moveToNextLine = \_ -> printText crlf
    clearLayout = clearLayoutD
    ringBell True = printText "\a"
    ringBell False = return ()
      
printText :: MonadIO m => String -> DumbTerm m ()
printText str = do
    h <- ask
    posixEncode str >>= liftIO . B.hPutStr h
    liftIO $ hFlush h

-- Things we can assume a dumb terminal knows how to do
cr,crlf :: String
crlf = "\r\n"
cr = "\r"

backs,spaces :: Int -> String
backs n = replicate n '\b'
spaces n = replicate n ' '


clearLayoutD :: MonadLayout m => DumbTerm m ()
clearLayoutD = do
    w <- maxWidth
    printText (cr ++ spaces w ++ cr)

-- Don't want to print in the last column, as that may wrap to the next line.
maxWidth :: MonadLayout m => DumbTerm m Int
maxWidth = asks (\lay -> width lay - 1)

drawLineDiff' :: MonadLayout m => LineChars -> LineChars -> DumbTerm m ()
drawLineDiff' (xs1,ys1) (xs2,ys2) = do
    Window {pos=p} <- get
    w <- maxWidth
    let (xs1',xs2') = matchInit xs1 xs2
    let newP = p + length xs2' - length xs1'
    let ys2' = take (w-newP) ys2
    if length xs1' > p  || newP >= w
        then refitLine (xs2,ys2)
        else do -- we haven't moved outside the margins
            put Window {pos=newP}
            case (xs1',xs2') of
                ([],[]) | ys1 == ys2    -> return () -- no change
                (_,[]) | xs1' ++ ys1 == ys2 -> -- moved left
                    printText $ backs (length xs1')
                ([],_) | ys1 == xs2' ++ ys2 -> -- moved right
                    printText xs2'
                _ -> let
                        extraLength = length xs1' + length ys1
                                    - length xs2' - length ys2
                     in printText $ backs (length xs1')
                        ++ xs2' ++ ys2' ++ clearDeadText extraLength
                        ++ backs (length ys2')

refitLine :: MonadLayout m => (String,String) -> DumbTerm m ()
refitLine (xs,ys) = do
    w <- maxWidth
    let xs' = dropFrames w xs
    let p = length xs'    
    put Window {pos=p}
    let ys' = take (w - p) ys
    let k = length ys'
    printText $ cr ++ xs' ++ ys'
        ++ spaces (w-k-p)
        ++ backs (w-p)
  where
    dropFrames w zs = case splitAt w zs of
                        (_,"") -> zs
                        (_,zs') -> dropFrames w zs'
    
clearDeadText :: Int -> String
clearDeadText n | n > 0 = spaces n ++ backs n
                | otherwise = ""