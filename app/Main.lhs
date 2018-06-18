\section{Main Program}
\begin{verbatim}
Copyright  Andrew Buttefield (c) 2017--18

LICENSE: BSD3, see file LICENSE at reasonEq root
\end{verbatim}
\begin{code}
module Main where

import System.Environment
import System.IO
import Data.Map (Map)
import qualified Data.Map as M
import Data.Set (Set)
import qualified Data.Set as S
import Data.List
import Data.Maybe
import Data.Char

import NiceSymbols hiding (help)

import Utilities
import LexBase
import Variables
import AST
import VarData
import SideCond
import Binding
import TermZipper
import Proof
import Propositions
import Instantiate
import TestRendering
import REPL
\end{code}

\begin{code}
name = "reasonEq"
version = "0.5.2.0"
\end{code}

\begin{code}
main :: IO ()
main
  = do args <- getArgs
       if "-g" `elem` args
       then do putStrLn "starting GUI..."
               gui (args \\ ["-g"])
       else do putStrLn "starting REPL..."
               repl args
\end{code}

\newpage
\subsection{System State}

Currently in prototyping mode,
so this is one large record.
Later we will nest things.
In order to support nested records properly,
for every record field \texttt{fld :: rec -> t},
we define \texttt{fld\_\_ :: (t -> t) -> rec -> rec}
and derive \texttt{fld\_ :: t -> rec -> rec}.
\begin{verbatim}
fld__ f r = r{fld = f $ fld r} ;  fld_ = fld__ . const
\end{verbatim}
\begin{code}
data REqState
 = ReqState {
      logic :: TheLogic
    , theories :: [Theory]
    , conj :: [NmdAssertion]
    , proof :: Maybe LiveProof
    , proofs :: [Proof]
    }
logic__    f r = r{logic    = f $ logic r}   ; logic_    = logic__     . const
theories__ f r = r{theories = f $ theories r}; theories_ = theories__  . const
conj__     f r = r{conj     = f $ conj r}    ; conj_     = conj__      . const
proof__    f r = r{proof    = f $ proof r}   ; proof_    = proof__     . const
proofs__   f r = r{proofs   = f $ proofs r}  ; proofs_   = proofs__    . const
\end{code}

At present, we assume development mode by default,
which currently initialises state based on the contents of
the hard-coded ``Propositional'' theory.
The normal ``user'' mode is not of much use right now.
\begin{code}
initState :: [String] -> IO REqState

initState ("user":_)
-- need to restore saved persistent state on startup
  = do putStrLn "Running in normal user mode."
       return
         $ ReqState thePropositionalLogic [] [] Nothing []

initState _
  = do putStrLn "Running in development mode."
       let reqs = ReqState thePropositionalLogic
                           [theoryPropositions]
                           propConjs Nothing []
       return reqs
\end{code}

\newpage
\subsection{GUI Top-Level}
\begin{code}
gui :: [String] -> IO ()
gui args = putStrLn $ unlines
         [ "Welcome to "++name++" "++version
         , "GUI N.Y.I.!"
         , "Goodbye" ]
\end{code}

\newpage
\subsection{REPL Top-Level}

We define our reasonEq REPL types first:
\begin{code}
type REqCmd       =  REPLCmd      REqState
type REqCmdDescr  =  REPLCmdDescr REqState
type REqExit      =  REPLExit     REqState
type REqCommands  =  REPLCommands REqState
type REqConfig    =  REPLConfig   REqState
\end{code}

Now we work down through the configuration components.
\begin{code}
reqPrompt :: Bool -> REqState -> String
reqPrompt _ _ = _equiv++" : "

reqEOFreplacmement = [nquit]

reqParser = charTypeParse

reqQuitCmds = [nquit] ; nquit = "quit"

reqQuit :: REqExit
-- may ask for user confirmation, and save? stuff..
reqQuit _ reqs = putStrLn "\nGoodbye!\n" >> return (True, reqs)
-- need to save persistent state on exit

reqHelpCmds = ["?","help"]

reqCommands :: REqCommands
reqCommands = [ cmdShow, cmdProve ]

-- we don't use these features in the top-level REPL
reqEndCondition _ = False
reqEndTidy _ reqs = return reqs
\end{code}

The configuration:
\begin{code}
reqConfig
  = REPLC
      reqPrompt
      reqEOFreplacmement
      reqParser
      reqQuitCmds
      reqQuit
      reqHelpCmds
      reqCommands
      reqEndCondition
      reqEndTidy
\end{code}

\begin{code}
repl :: [String] -> IO ()
repl args
  = do reqs0 <- initState args
       runREPL reqWelcome reqConfig reqs0
       return ()

reqWelcome = unlines
 [ "Welcome to the "++name++" "++version++" REPL"
 , "Type '?' for help."
 ]
\end{code}


\newpage
\subsection{Show Command }
\begin{code}
cmdShow :: REqCmdDescr
cmdShow
  = ( "sh"
    , "show parts of the prover state"
    , unlines
        [ "sh "++shLogic++" -- show current logic"
        , "sh "++shTheories++" -- show theories"
        , "sh "++shConj++" -- show current conjectures"
        , "sh "++shLivePrf++" -- show current proof"
        , "sh "++shProofs++" -- show completed proofs"
        ]
    , showState )

shLogic = "="
shTheories = "t"
shConj = "c"
shLivePrf = "p"
shProofs = "P"

showState [cmd] reqs
 | cmd == shLogic     =  doshow reqs $ showLogic $ logic reqs
 | cmd == shTheories  =  doshow reqs $ showTheories $ theories reqs
 | cmd == shConj      =  doshow reqs $ showNmdAssns  $ conj  reqs
 | cmd == shLivePrf   =  doshow reqs $ showLivePrf $ proof reqs
 | cmd == shProofs    =  doshow reqs $ showProofs $ proofs reqs
showState _ reqs      =  doshow reqs "unknown 'show' option."


doshow reqs str  =  putStrLn str >> return reqs
\end{code}

\newpage
\subsection{Prove Command}
\begin{code}
cmdProve :: REqCmdDescr
cmdProve
  = ( "prove"
    , "do a proof"
    , unlines
       [ "prove i"
       , "i : conjecture number"
       , "no arg required if proof already live."
       ]
    , doProof )


doProof args reqs
  = case proof reqs of
      Nothing
       ->  do putStrLn "No current proof, will try to start one."
              case nlookup (getProofArgs args) (conj reqs) of
                Nothing  ->  do putStrLn "invalid conjecture number"
                                return reqs
                Just nconj@(nm,asn)
                 -> do let strats
                            = availableStrategies (logic reqs)
                                                  thys
                                                  nconj
                       putStrLn $ numberList presentSeq $ strats
                       putStr "Select sequent:- " ; choice <- getLine
                       let six = readInt choice
                       case nlookup six strats of
                         Nothing   -> doshow reqs "Invalid strategy no"
                         Just seq
                           -> proofREPL reqs (launchProof thys nm asn seq)
      Just proof
       ->  do putStrLn "Back to current proof."
              proofREPL reqs proof
  where
    getProofArgs [] = 0
    getProofArgs (a:_) = readInt a
    thys = theories reqs
\end{code}

Presenting a sequent for choosing:
\begin{code}
presentSeq (str,seq)
  = "'" ++ str ++ "':  "
    ++ presentHyp (hyp seq)
    ++ " " ++ _vdash ++ " " ++
    trTerm 0 (cleft seq)
    ++ " = " ++
    trTerm 0 (cright seq)

presentHyp hthy
  = intercalate "," $ map (trTerm 0 . fst . snd . fst) $ laws hthy
\end{code}

\newpage
\subsubsection{Proof REPL}

We start by defining the proof REPL state:
\begin{code}
type ProofState
  = ( REqState   -- reasonEq state
    , LiveProof )  -- current proof state
\end{code}
From this we can define most of the REPL configuration.
\begin{code}
proofREPLprompt justHelped (_,proof)
  | justHelped  =  unlines' [ dispLiveProof proof
                            , "proof: "]
  | otherwise   =  unlines' [ clear -- clear screen, move to top-left
                            , dispLiveProof proof
                            , "proof: "]

proofEOFReplacement = []

proofREPLParser = charTypeParse

proofREPLQuitCmds = ["q"]

proofREPLQuit args (reqs,proof)
  = do putStr "Proof Incomplete, Abandon ? [Y] : "
       hFlush stdout
       inp <- getLine
       if inp == "Y"
        then return (True,( proof_ Nothing      reqs, proof))
        else return (True,( proof_ (Just proof) reqs, proof))

proofREPLHelpCmds = ["?"]

proofREPLEndCondition (reqs,proof)
  =  proofComplete (logic reqs) proof

proofREPLEndTidy _ (reqs,proof)
  = do putStrLn "Proof Complete"
       let prf = finaliseProof proof
       putStrLn $ displayProof prf
       return ( proof_ Nothing $ proofs__ (prf:) reqs, proof)
  -- Need to remove from conjectures and add to Laws
\end{code}

\begin{code}
proofREPLConfig
  = REPLC
      proofREPLprompt
      proofEOFReplacement
      proofREPLParser
      proofREPLQuitCmds
      proofREPLQuit
      proofREPLHelpCmds
      ( map clearLong
            [ goDownDescr
            , goUpDescr
            , matchLawDescr
            , applyMatchDescr
            , lawInstantiateDescr
            ])
      proofREPLEndCondition
      proofREPLEndTidy
\end{code}

This repl runs a proof.
\begin{code}
proofREPL reqs proof
 = do (reqs',_) <- runREPL
                       (clear++"Prover starting...")
                       proofREPLConfig
                       (reqs,proof)
      return reqs'

args2int args = if null args then 0 else readInt $ head args
\end{code}

Focus movement commands
\begin{code}
goDownDescr = ( "d", "down", "d n  -- down n", goDown )

goDown :: REPLCmd (REqState, LiveProof)
goDown args (reqs,
             proof@(LP nm asn sc strat mcs (tz,seq') dpath _ steps ))
  = let i = args2int args
        (ok,tz') = downTZ i tz
    in if ok
        then return (reqs, (LP nm asn sc strat mcs
                               (tz',seq') (dpath++[i]) [] steps))
        else return (reqs, proof)

goUpDescr = ( "u", "up", "u  -- up", goUp )

goUp _ (reqs, proof@(LP nm asn sc strat mcs (tz,seq') dpath _ steps ))
  = let (ok,tz') = upTZ tz in
    if ok
    then return (reqs, (LP nm asn sc strat mcs
                           (tz',seq') (init dpath) [] steps))
    else return (reqs, proof)
\end{code}

\newpage
Law Matching
\begin{code}
matchLawDescr = ( "m", "match laws", "m  -- match laws", matchLawCommand )

matchLawCommand _ (reqs, proof@(LP nm asn sc strat mcs sz@(tz,_) dpath _ steps))
  = do putStrLn ("Matching "++trTerm 0 goalt)
       let matches = matchInContexts (logic reqs) mcs goalt
       return (reqs, (LP nm asn sc strat mcs sz dpath matches steps))
  where goalt = getTZ tz

applyMatchDescr = ( "a", "apply match"
                  , "a i  -- apply match number i", applyMatch)

applyMatch args (reqs,
                 proof@(LP nm asn sc strat mcs (tz,seq') dpath matches steps))
  = let i = args2int args in
    case alookup i matches of
     Nothing -> do putStrLn ("No match numbered "++ show i)
                   return (reqs, proof)
     Just (_,(lnm,lasn,bind,repl))
      -> case instantiate bind repl of
          Nothing -> do putStrLn "Apply failed !"
                        return (reqs, proof)
          Just brepl
            -> do putStrLn ("Applied law '"++lnm++"' at "++show dpath)
                  return ( reqs,
                           (LP nm asn sc strat
                               mcs ((setTZ brepl tz),seq')
                               dpath []
                               ((("match "++lnm,bind,dpath), exitTZ tz):steps)) )
\end{code}

Replacing \textit{true} by a law, with unknown variables
suitably instantiated.
\begin{code}

lawInstantiateDescr = ( "i", "instantiate"
                      , "i  -- instantiate a true focus with an law"
                      , lawInstantiateProof )
lawInstantiateProof _ (reqs, proof@(LP nm asn sc strat
                                       mcs sz@(tz,_) dpath matches steps))
  | currt /= true
    = do putStrLn ("Can only instantiate an law over "++trTerm 0 true)
         return (reqs, proof)
  | otherwise
    = do putStrLn $ showLaws rslaws
         putStr "Pick a law : " ; input <- getLine
         case input of
           str@(_:_) | all isDigit str
             -> case nlookup (read str) rslaws of
                 Just law@((nm,asn),prov)
                   -> do putStrLn ("Law Chosen: "++nm)
                         instantiateLaw reqs proof law
                 _ -> return (reqs, proof)
           _ -> return (reqs, proof)
  where
    currt = getTZ tz; true = theTrue $ logic reqs
    thrys = theories reqs
    rslaws = if null thrys then [] else laws (head thrys)

instantiateLaw reqs proof@(LP pnm asn psc strat
                              mcs (tz,seq') dpath matches steps)
                    law@((lnm,(lawt,lsc)),_)
 = do lbind <- generateLawInstanceBind (map knownV $ theories reqs)
                                       (exitTZ tz) psc law
      case instantiateSC lbind lsc of
        Nothing -> do putStrLn "instantiated law side-cond is false"
                      return (reqs, proof)
        Just ilsc
          -> do putStrLn $ trBinding lbind
                case mrgSideCond psc ilsc of
                  Nothing -> do putStrLn "side-condition merge failed"
                                return (reqs, proof)
                  Just nsc ->
                    do  ilawt <- instantiate lbind lawt
                        return ( reqs
                               , (LP pnm asn nsc strat
                                     mcs (setTZ ilawt tz,seq')
                                     dpath
                                     matches
                                     ( ( ("instantiate "++lnm,lbind,dpath)
                                       , exitTZ tz )
                                       : steps ) ) )
\end{code}

\newpage

Dialogue to get law instantiation binding.
We want a binding for every unknown variable in the law.
We display all such unknowns, and then ask for instantiations.
\begin{code}
generateLawInstanceBind vts gterm gsc law@((lnm,(lawt,lsc)),lprov)
 = do let lFreeVars = stdVarSetOf $ S.filter (isUnknownGVar vts)
                                  $ freeVars lawt
      putStrLn ("Free unknown law variables: "++trVariableSet lFreeVars)
      let subGTerms = reverse $ subTerms gterm
      -- let subGVars = map theVar $ filter isVar subGTerms
      requestInstBindings emptyBinding subGTerms $ S.toList lFreeVars
\end{code}

\begin{code}
requestInstBindings bind gterms []  =  return bind
requestInstBindings bind gterms vs@(v:vrest)
 = do putStrLn "Goal sub-terms:"
      putStrLn $ numberList (trTerm 0) gterms
      putStr ("Binding for "++trVar v++" ? ") ; input <- getLine
      case input of
       str@(_:_) | all isDigit str
         -> case nlookup (read str) $ gterms of
             Just gterm
               -> do bind' <- bindVarToTerm v gterm bind
                     requestInstBindings bind' gterms vrest
             _ -> requestInstBindings bind gterms vs
       _ -> requestInstBindings bind gterms vs
\end{code}


Different list lookup approaches:
\begin{code}
-- list lookup by number [1..]
nlookup i things
 | i < 1 || null things  =  Nothing
nlookup 1 (thing:rest)   =  Just thing
nlookup i (thing:rest)   =  nlookup (i-1) rest

-- association list lookup
alookup name [] = Nothing
alookup name (thing@(n,_):rest)
  | name == n  =  Just thing
  | otherwise  =  alookup name rest
\end{code}

Screen clearing:
\begin{code}
clear = "\ESC[2J\ESC[1;1H"
clearIt str = clear ++ str
clearLong :: REPLCmdDescr s -> REPLCmdDescr s
clearLong (nm,short,long,func) = (nm,short,clearIt long,func)
\end{code}
