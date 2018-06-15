\section{Generic REPL Code}
\begin{verbatim}
Copyright  Andrew Buttefield (c) 2017--18

LICENSE: BSD3, see file LICENSE at reasonEq root
\end{verbatim}
\begin{code}
module REPL (
    REPLParser, REPLArguments, idParse, wordParse, charTypeParse
  , REPLCmd, REPLCmdDescr, REPLExit, REPLCommands
  , REPLConfig(..)
  , runREPL
  )
where

import System.Console.Haskeline
import Control.Monad.IO.Class
import Data.List
import Data.Char
\end{code}

\subsection{REPL Introduction}

A ``REPL''%
\footnote{
Read-Execute-Print-Loop,
}%
 involves getting user-input,
and then using that to produce some form of state transformation
with user feedback.
Here we provide a pre-packaged REPL, parameterised by:
\begin{itemize}
  \item Welcome (\texttt{wlcm})
  \item user prompt and parsing (\texttt{pp})
  \item command descriptors (\texttt{cds})
  \item state (\texttt{state})
\end{itemize}

We consider a REPL as always having two special-purpose commands,
one to exit the REPL, another to provide help,
while the rest are viewed as I/O actions that also modify state.

\newpage
A parser converts strings to lists of strings.
The key point here is that the first string, if present,
determines what command will be run,
with the remaining strings passed as arguments to that command
We define some simple obvious parsers as well.
\begin{code}
type REPLParser = String -> [String]
type REPLArguments = [String]

idParse, wordParse, charTypeParse :: REPLParser

idParse s = [s] -- return user string completely unaltered

wordParse = words -- break into max-length runs without whitespace

charTypeParse -- group letter,digits, and other non-print
 = concat . map (segment []) . words
 where
   segment segs "" = reverse segs
   segment segs (c:cs)
    | isAlpha c = segment' isAlpha segs [c] cs
    | isDigit c = segment' isDigit segs [c] cs
    | c == '-'  = segment' isDigit segs [c] cs
    | otherwise = segment' notAlphNum segs [c] cs
   segment' p segs [] ""  = reverse segs
   segment' p segs seg ""  = reverse (reverse seg:segs)
   segment' p segs seg str@(c:cs)
    | p c = segment' p segs (c:seg) cs
    | otherwise  = segment (reverse seg:segs) str
   notAlphNum c
    | isAlpha c  =  False
    | isDigit c  =  False
    | otherwise  =  True
\end{code}

\newpage
\begin{code}
type REPLCmd state = REPLArguments -> state -> IO state
type REPLCmdDescr state
  = ( String     -- command name
    , String     -- short help for this command
    , String     -- long help for this command
    , REPLCmd state)  -- command function
type REPLExit state = REPLArguments -> state -> IO (Bool,state)
type REPLCommands state = [REPLCmdDescr state]
\end{code}


\subsubsection{Command Respository Lookup}
\begin{code}
cmdLookup :: String -> REPLCommands state -> Maybe (REPLCmdDescr state)
cmdLookup s []= Nothing
cmdLookup s (cd@(n,_,_,_):rest)
 | s == n     =  Just cd
 | otherwise  =  cmdLookup s rest
\end{code}


We have a configuration that defines the REPL behaviour
that does not change during its lifetime:
\begin{code}
data REPLConfig state
  = REPLC {
      replPrompt :: state -> String
    , replEOFReplacement :: [String]
    , replParser :: REPLParser
    , replQuitCmds :: [String]
    , replQuit :: REPLExit state
    , replHelpCmds :: [String]
    , replCommands :: REPLCommands state
    , replEndCondition :: state -> Bool
    , replEndTidy :: REPLCmd state
    }

defConfig
  = REPLC
      (const "repl: ")
      ["ignoring EOF"]
      charTypeParse
      ["quit","x"]
      defQuit
      ["help","?"]
      tstCmds
      defEndCond
      defEndTidy

defQuit _ s
  = do putStrLn "\nGoodbye!\n"
       return (True,s)

tstCmds
  = [ ("test"
      , "simple test"
      , "raises all arguments to uppercase"
      , tstCmd
      )
    ]

tstCmd args s
  = do putStrLn (show $ map (map toUpper) args)
       putStrLn "Test complete"
       return s

defEndCond _ = False
defEndTidy _ s = return s
\end{code}

\begin{code}
runREPL :: String
        -- -> (state -> String) -> parser -> cds -> exit
        -> REPLConfig state
        -> state -> IO state
runREPL wlcm config s0
  = runInputT defaultSettings (welcome wlcm >> loopREPL config s0)

welcome :: String -> InputT IO ()
welcome wlcm = outputStrLn wlcm
\end{code}

Loop simply gets users input and dispatches on it
\begin{code}
loopREPL :: REPLConfig state -> state -> InputT IO state
loopREPL config s
  = if replEndCondition config s
     then liftIO $ replEndTidy config [] s
     else do inp <- inputREPL config s
             dispatchREPL config s inp
\end{code}

Input generates a prompt that may or may not depend on the state,
and then checks and transforms
\begin{code}
inputREPL :: REPLConfig state -> state -> InputT IO [String]
inputREPL config s
  = do minput <- getInputLine (replPrompt config s)
       case minput of
         Nothing     ->  return $ replEOFReplacement config
         Just input  ->  return $ replParser config input
\end{code}

Dispatch first checks input to see if it requires exiting,
in which case it invokes the exit protocol (which might not exit!).
Then it sees if the help command has been given,
and enacts that.
Otherwise it executes the designated command.
\begin{code}
dispatchREPL :: REPLConfig state -> state -> [String] -> InputT IO state
dispatchREPL config s []
  = loopREPL config s
dispatchREPL config s (cmd:args)
  | cmd `elem` replQuitCmds config
    = do (go,s') <- liftIO $ replQuit config args s
         if go then return s'
               else loopREPL config s'
  | cmd `elem` replHelpCmds config
    = do helpREPL config s args
         loopREPL config s
  | otherwise
    = case cmdLookup cmd (replCommands config) of
        Nothing
          -> do outputStrLn ("No such command '"++cmd++"'")
                loopREPL config s
        Just (_,_,_,cmdFn)
          -> do s' <- liftIO $ cmdFn args s
                loopREPL config s'
\end{code}

Help with no arguments shows the short help for all commands.
Help with an argument that corresponds to a command shows the
long help for that command.
\begin{code}
helpREPL :: REPLConfig state -> state -> [String] -> InputT IO ()
helpREPL config s []
  = do outputStrLn ""
       outputStrLn ((intercalate "," $ replQuitCmds config)++" -- exit")
       outputStrLn ((intercalate "," $ replHelpCmds config)++" -- this help text")
       outputStrLn ((intercalate "," $ replHelpCmds config)++" <cmd> -- help for <cmd>")
       shortHELP $ replCommands config
       outputStrLn ""
helpREPL config s (cmd:_) = longHELP cmd (replCommands config)
\end{code}

\begin{code}
shortHELP :: REPLCommands state -> InputT IO ()
shortHELP [] = return ()
shortHELP ((nm,shelp,_,_):cmds)
  = do outputStrLn ( nm ++ " -- " ++ shelp )
       shortHELP cmds
\end{code}

\begin{code}
longHELP :: String -> REPLCommands state -> InputT IO ()
longHELP cmd [] = outputStrLn ("No such command: '"++cmd++"'")
longHELP cmd ((nm,_,lhelp,_):cmds)
  | cmd == nm  = outputStrLn ( "\n" ++ cmd ++ " -- " ++ lhelp ++ "\n")
  | otherwise  =  longHELP cmd cmds
\end{code}
