\section{Universal Closure}
\begin{verbatim}
Copyright  Andrew Buttefield (c) 2019

LICENSE: BSD3, see file LICENSE at reasonEq root
\end{verbatim}
\begin{code}
{-# LANGUAGE PatternSynonyms #-}
module UClose (
  uCloseConjs, uCloseName, uCloseTheory
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

import StdSignature
import Equivalence
import Negation
import Disjunction
import Conjunction
import AndOrInvert
import Implication
import Equality
import ForAll
import Exists
import TestRendering
\end{code}


\newpage
\subsection{Introduction}


Here we present a hard-coded implementation of
predicate equational reasoning,
as inspired by Gries \& Schneider\cite{gries.93},
Gries' notes from the 1996 Marktoberdorf Summer School\cite{gries.97},
Tourlakis \cite{journals/logcom/Tourlakis01},
and described in \cite{DBLP:conf/utp/Butterfield12}.
However we adopt here a formulation closer to that of Gries\&Schneider,
as the Tourlakis form has useful laws such as the one-point rules
derived from his axioms by meta-proofs
\emph{that use non-equational reasoning}.

Reference \cite{gries.97} has only recently come to our attention,
where $[\_]$ is defined,
 as the same thing as the temporal box operator ($\Box$)
 of the logic C \cite[Section 5.2, p113; Table 8, p114]{gries.97}.

The inference rules and axioms,
given that $\Diamond P = \lnot \Box(\lnot P)$,
  are:
\begin{eqnarray*}
   \vdash P ~~\longrightarrow~~ \vdash \Box P
   && \textbf{Necessitation}
\\ \Box P    ~~\implies~~   P
   && \textbf{$\Box$-Instantiation}
\\ \Box(P\implies Q) ~~\implies~~ (\Box P \implies \Box Q)
   && \textbf{Monotonicity}
\\ \Diamond P ~~\implies~~ \Box \Diamond P
   && \textbf{Necessarily Possible}
\\ \vdash P ~~\longrightarrow~~ \vdash P^v_Q
   && \textbf{Textual Substitution}
\end{eqnarray*}
where the first four belong to temporal logic S5,
and the fifth produces logic C.
Logic C is both sound and complete, while S5 is incomplete.

In our notation we have two meta-theorems (1st and 5th above),
\begin{eqnarray*}
   P \text{ a theorem} & \text{implies} & [P] \text{ a theorem}
\\ P \text{ a theorem} & \text{implies} & P[Q/v] \text{ a theorem,}
\end{eqnarray*}
a definition $\langle P \rangle = \lnot[\lnot P]$,
and three axioms (2nd through 4th above)
\begin{eqnarray*}
   ~[P] &\implies& P
\\ ~[P\implies Q] &\implies& ([P] \implies [Q])
\\ \langle P \rangle &\implies& [\langle P \rangle].
\end{eqnarray*}

In a similar style, here is the ``temporal'' axiomatisation,
using the Gries notation:

$$
\AXUNIVCLOSEASBOX
$$

These don't seem helpful at all.
I can't use them to prove \CJUnivIdemN\ or \CJandUnivDistrN,
for example.
However, with \AXUnivDefN\ we can prove \AXBoxInstN,
\AXBoxMonoN, and \AXNecPossN.
So we make the latter three into conjectures.
The $\Diamond$ operator is just existential closure,
a.k.a. satisfiability.

$$
\AXSATISFIABLE
$$

So, here is the resulting axiomatisation and set of conjectures:
$$
\AXUNIVCLOSE
$$
$$
\CJUNIVCLOSE
$$

\subsection{Predicate Infrastructure}

We need to build some infrastructure here.
This consists of the predicate variables $P$ and $Q$,
the constant  $[\_]$,
and a generic binder variable: $\lst x$.

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

\newpage
\subsection{Universal Axioms}

% \begin{array}{lll}
%    \AXUnivDef & \AXUnivDefS & \AXUnivDefN
% \\ \AXPEqDef  & \AXPEqDefS  & \AXPEqDefN
% \end{array}

$$
  \begin{array}{lll}
     \AXUnivDef & \AXUnivDefS & \AXUnivDefN
  \end{array}
$$\par\vspace{-8pt}
\begin{code}
axUnivDef = preddef ("[]" -.- "def")
                    (univ p  === forall [xs] p)
                    ([xs] `exCover` gvP)
\end{code}

$$
  \begin{array}{lll}
     \AXsatDef & \AXsatDefS & \AXsatDefN
  \end{array}
$$\par\vspace{-8pt}
\begin{code}
axSatDef = preddef ("sat" -.- "def")
                  ( sat p === mkNot (univ (mkNot p)) )
                  scTrue
\end{code}

We now collect our axiom set:
\begin{code}
uCloseAxioms :: [Law]
uCloseAxioms
  = map labelAsAxiom
      [ axUnivDef, axSatDef ]
\end{code}


\subsection{Universal Conjectures}

$$
  \begin{array}{lll}
     \CJUnivIdem & \CJUnivIdemS & \CJUnivIdemN
  \end{array}
$$\par\vspace{-8pt}
\begin{code}
cjUnivIdem = preddef ("[]" -.- "idem")
                     (univ (univ p) === univ p)
                     scTrue
\end{code}


$$
  \begin{array}{lll}
     \CJandUnivDistr & \CJandUnivDistrS & \CJandUnivDistrN
  \end{array}
$$\par\vspace{-8pt}
\begin{code}
cjAndUnivDistr = preddef ("land" -.- "[]" -.- "distr")
                (univ p /\ univ q === univ (p /\ q))
                scTrue
\end{code}

$$
  \begin{array}{lll}
     \CJtrueUniv & \CJtrueUnivS & \CJtrueUnivN
  \end{array}
$$\par\vspace{-8pt}
\begin{code}
cjUnivTrue = preddef ("univ" -.- "true")
                     (univ trueP === trueP)
                     scTrue
\end{code}

$$
  \begin{array}{lll}
     \CJfalseUniv & \CJfalseUnivS & \CJfalseUnivN
  \end{array}
$$\par\vspace{-8pt}
\begin{code}
cjUnivFalse = preddef ("univ" -.- "False")
                      (univ falseP === falseP)
                      scTrue
\end{code}

$$
  \begin{array}{lll}
     \CJallUnivClosed & \CJallUnivClosedS & \CJallUnivClosedN
  \end{array}
$$\par\vspace{-8pt}
\begin{code}
cjUnivAllClosed = preddef ("univ" -.- "forall" -.- "closed")
                          ((forall [xs] $ univ p) === univ p)
                          scTrue
\end{code}

$$
  \begin{array}{lll}
     \CJanyUnivClosed & \CJanyUnivClosedS & \CJanyUnivClosedN
  \end{array}
$$\par\vspace{-8pt}
\begin{code}
cjUnivAnyClosed = preddef ("univ" -.- "exists" -.- "closed")
                          ((exists [xs] $ univ p) === univ p)
                          scTrue
\end{code}


$$
  \begin{array}{lll}
     \CJunivInst & \CJunivInstS & \CJunivInstN
  \end{array}
$$\par\vspace{-8pt}
\begin{code}
cjUnivInst = preddef ("univ" -.- "inst")
                (univ p ==> p)
                scTrue
\end{code}

$$
  \begin{array}{lll}
     \CJunivMono & \CJunivMonoS & \CJunivMonoN
  \end{array}
$$\par\vspace{-8pt}
\begin{code}
cjUnivMono = preddef ("univ" -.- "mono")
                ( univ (p ==> q) ==> (univ p ==> univ q))
                scTrue
\end{code}

$$
  \begin{array}{lll}
     \CJnecPoss & \CJnecPossS & \CJnecPossN
  \end{array}
$$\par\vspace{-8pt}
\begin{code}
cjNecPoss = preddef ("necessary" -.- "poss")
                ( sat p ==> univ (sat p) )
                scTrue
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

We now collect our conjecture set:
\begin{code}
uCloseConjs :: [NmdAssertion]
uCloseConjs
  = [ cjUnivIdem, cjAndUnivDistr
    , cjUnivTrue, cjUnivFalse
    , cjUnivAllClosed, cjUnivAnyClosed
    , cjUnivInst, cjUnivMono, cjNecPoss ]
\end{code}


\subsection{The Predicate Theory}

\begin{code}
uCloseName :: String
uCloseName = "UClose"
uCloseTheory :: Theory
uCloseTheory
  =  Theory { thName  =  uCloseName
            , thDeps  =  [ existsName
                         , forallName
                         , equalityName
                         , implName
                         , aoiName
                         , conjName
                         , disjName
                         , notName
                         , equivName
                         ]
            , known   =  newVarTable
            , laws    =  uCloseAxioms
            , proofs  =  []
            , conjs   =  uCloseConjs
            }
\end{code}