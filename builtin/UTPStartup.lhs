\section{UTP Start-up}
\begin{verbatim}
Copyright  Andrew Buttefield (c) 2019

LICENSE: BSD3, see file LICENSE at reasonEq root
\end{verbatim}
\begin{code}
{-# LANGUAGE PatternSynonyms #-}
module UTPStartup (
  univ
, utpStartupConjs, utpStartupName, utpStartupTheory
) where

import Data.Maybe
import qualified Data.Set as S

import NiceSymbols

import Utilities
import LexBase
import Variables
import AST
import SideCond
import VarData
import Laws
import Proofs
import Theories

import PropAxioms
import PropSubst
import PropEquiv
import PropNot
import PropDisj
import PropConj
import PropMixOne
import PropImpl
import Equality
import PredAxioms
import PredExists
import PredUniv
\end{code}


\newpage
\subsection{Introduction}


This builtin theory is being used to prototype the building of UTP
support of top of the propostional and predicate foundation already done.


\subsection{Predicate Infrastructure}

We need to build some infrastructure here.

\subsubsection{Predicate and Expression Variables}

\begin{code}
vP = Vbl (fromJust $ ident "P") PredV Static
gvP = StdVar vP
p = fromJust $ pVar vP
q = fromJust $ pVar $ Vbl (fromJust $ ident "Q") PredV Static
\end{code}

\subsubsection{Predicate Constants}


\subsubsection{Generic Variables}

\begin{code}
vx = Vbl (fromJust $ ident "x") ObsV Static ; x = StdVar vx
lvxs = LVbl vx [] [] ; xs = LstVar lvxs
\end{code}

\begin{code}
r = fromJust $ pVar $ Vbl (fromJust $ ident "R") PredV Static
\end{code}

\subsubsection{Propositional Type}

\begin{code}
bool = GivenType $ fromJust $ ident $ _mathbb "B"
\end{code}

\subsubsection{Propositional Constants}

\begin{code}
trueP  = Val P $ Boolean True
falseP = Val P $ Boolean False
\end{code}

\begin{code}
ve = Vbl (fromJust $ ident "e") ExprV Static
lves = LVbl ve [] []

sub p = Sub P p $ fromJust $ substn [] [(lvxs,lves)]
\end{code}



\newpage
\subsection{UTP-Startup Axioms}

\subsubsection{Axiom 1}
$$
  \begin{array}{lll}
     P \lor (Q \lor \lnot Q) &  & \QNAME{UTP-ax-001}
  \end{array}
$$\par\vspace{-8pt}
\begin{code}
axUTP001 = preddef ("UTP" -.- "ax" -.- "001")
                    (p \/ (q \/ mkNot q))
                    scTrue
\end{code}


\subsection{UTP-Startup Conjectures}

\subsubsection{Conjecture 1}
$$
  \begin{array}{lll}
     (P \lor Q) \lor \lnot Q & \lst x \notin Q & \QNAME{UTP-cj-001}
  \end{array}
$$\par\vspace{-8pt}
\begin{code}
cjUTP0001 = preddef ("UTP" -.- "cj" -.- "001")
                     ((p \/ q) \/ mkNot q)
                     ([xs] `notin` gvP)
\end{code}



% %% TEMPLATE
% $$
%   \begin{array}{lll}
%      law & sc & name
%   \end{array}
% $$\par\vspace{-8pt}
% \begin{code}
% cjXXX = preddef ("law" -.- "name")
%                 p
%                 scTrue
% \end{code}

We now collect our axiom set:
\begin{code}
utpStartupAxioms :: [Law]
utpStartupAxioms
  = map labelAsAxiom
      [ axUTP001 ]
\end{code}


We now collect our conjecture set:
\begin{code}
utpStartupConjs :: [NmdAssertion]
utpStartupConjs
  = [ cjUTP0001 ]
\end{code}


\subsection{The Predicate Theory}

\begin{code}
utpStartupName :: String
utpStartupName = "UTPStartup"
utpStartupTheory :: Theory
utpStartupTheory
  =  Theory { thName  =  utpStartupName
            , thDeps  =  [ predUnivName
                         , predExistsName
                         , predAxiomName
                         , equalityName
                         , propSubstName
                         , propImplName
                         , propMixOneName
                         , propConjName
                         , propDisjName
                         , propNotName
                         , propEquivName
                         , propAxiomName
                         ]
            , known   =  newVarTable
            , laws    =  utpStartupAxioms
            , proofs  =  []
            , conjs   =  utpStartupConjs
            }
\end{code}