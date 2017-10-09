\section{Matching}
\begin{verbatim}
Copyright  Andrew Buttefield (c) 2017

LICENSE: BSD3, see file LICENSE at reasonEq root
\end{verbatim}
\begin{code}
{-# LANGUAGE PatternSynonyms #-}
module Matching
( match
, tMatch, tsMatch
, tvMatch, tkvMatch
, vMatch, bvMatch
, vsMatch, vlMatch
, sMatch
) where
import Data.Maybe (isJust,fromJust)
import Data.Map (Map)
import qualified Data.Map as M
import Data.Set (Set)
import qualified Data.Set as S
import Control.Monad
import Data.List

import Utilities
import LexBase
import AST
import VarData
import Binding
\end{code}

\subsection{Matching Principles}

We want to match a candidate term ($C$) against a pattern term ($P$)
in some context ($\Gamma$),
to obtain a binding ($\beta$), if successful,
of pattern variables to appropriate term components.
$$
\Gamma \vdash C :: P  \leadsto \beta
$$
The context has two components,
the first ($\kappa$) being the known variables,
and the second ($B$) keeping track of bound variables.
We need to track bound variables for both
the candidate ($B_C$)
and pattern ($B_P$)
$$
\kappa;(B_C,B_P) \vdash C :: P  \leadsto \beta
$$
The use-case that is most common in the planned use for matching
is where we want to match a single candidate against many patterns.
We expect most such matches to fail,
and so we want to design our algorithms
to discover failure as fast as possible.
This means doing top-level structural matching first,
and only then trying the more complex and tricky matching
of variable lists and sets.

The idea is that we attempt to construct a binding on-the-fly,
doing matching on one sub-component at a time,
passing the partial binding result along and attempting to add new bindings
directly into it.
$$
\kappa;\beta;(B_C,B_P) \vdash C :: P \leadsto \beta'
$$
We also posit a binary partial operator ($\uplus$) that merges two bindings
as long as overlapping entries agree,
so the assertion $\beta = \beta_1 \uplus \beta_2$ is true only if all overlapping entries in the $\beta_i$ agree,
and $\beta$ corresponds to their union.

We are not normally interested in the reason why a match fails,
so will generally use the \texttt{Maybe} type constructor.
However we code for a general monad with meaningful \texttt{fail} messages
to make it easier to debug or test.
We also need to support the idea that some patterns may match a given
candidate in more than one way,
so we would like to return a list of bindings,
leading us to adopt the \texttt{MonadPlus} class.
$$
\kappa;\beta;(B_C,B_P) \vdash C :: P
\leadsto \langle \beta'_1 , \dots , \beta'_n \rangle
$$
Each of the $\beta'_i$
has the general form $\beta'_{i1} \uplus \dots \uplus \beta'_{ik_i}$,
and a rule applies provided at least one of the $\beta'_i$ is defined.
We write $\langle\beta\rangle$ as $\beta$
and in most rules we omit irrelevant parts of the context.
\newpage
\subsection{Matching Types}

We introduce some type and value synonyms,
to make type-signatures more informative.
\begin{code}
type Pattern = Term
type Candidate = Term
type BVS = Set GenVar
type PBVS = BVS
type CBVS = BVS

noBVS = S.empty
\end{code}

We will want to add in sets and lists of variables
into the bound-variable sets.
\begin{code}
addBoundVarSet :: VarSet -> BVS -> BVS
vs `addBoundVarSet` bvs  =  vs `S.union` bvs

addBoundVarList :: VarList -> BVS -> BVS
vl `addBoundVarList` bvs  =  (S.fromList vl) `S.union` bvs
\end{code}

\subsection{Top-level Matching}

At the top-level we have the known-variable information
in the form of a sequence $\kappa s$ of known variable tables,
and the pattern and candidate terms,
and we hope to get at least one binding.
We initialise the bound-variable sets to empty ($\emptyset$)
and the bindings already obtained to the null map ($\theta$).
$$
\inferrule
   {\kappa s;\theta;(\emptyset,\emptyset) \vdash C :: P \leadsto \beta s}
   {\kappa s \vdash C :: P \leadsto \beta s}
   \quad
   \texttt{match}
$$
\begin{code}
match :: MonadPlus mp => [VarTable] -> Candidate -> Pattern -> mp Binding
match vts c p  =  tMatch vts emptyBinding noBVS noBVS c p
\end{code}

\subsection{Term Matching}

\begin{code}
tMatch, tMatch' ::
  MonadPlus mp => [VarTable] -> Binding -> CBVS -> PBVS
               -> Candidate -> Pattern -> mp Binding
\end{code}

We note that the \texttt{TermKind} of pattern and candidate must match.
Either both are predicates,
or both are expressions with the type of the candidate
being an sub-type of the pattern.
\begin{code}
tMatch vts bind cbvs pbvs tC tP
 = case (termkind tC, termkind tP) of
    (P,P)                       ->  tMatch' vts bind cbvs pbvs tC tP
    (E typC, E typP)
      | typC `isSubTypeOf` typP   ->  tMatch' vts bind cbvs pbvs tC tP
    _ -> fail "tMatch: incompatible termkinds."
\end{code}

Term-matching is defined inductively over the pattern type.

We start with the simple value and structural composite matches,
and then proceed to look at variable, binder and substitution patterns.

\subsubsection{Value Term-Pattern (\texttt{Val})}
Values only match themselves.
$$
\inferrule
   {{\kk k}_C = {\kk k}_P}
   {\beta \vdash {\kk k}_C :: {\kk k}_P \leadsto \beta}
   \quad
   \texttt{tMatch Val}
$$
\begin{code}
tMatch' _ bind _ _ kC@(Val _ _) kP@(Val _ _)
 | kC == kP  =  return bind
\end{code}

\subsubsection{Variable Term-Pattern (\texttt{Var})}
Variable matching is complicated, so we farm it out,
as long as \texttt{TermKind}s match.
$$
\inferrule
   {\beta \vdash t_C :: v_P \leadsto \beta'}
   {\beta \vdash t_C :: {\vv v}_P \leadsto \beta'}
   \quad
   \texttt{tMatch Var}
$$
\begin{code}
tMatch' vts bind cbvs pbvs tC (Var tkP vP)
  | tkP == termkind tC  =  tvMatch vts bind cbvs pbvs tC tkP vP
\end{code}


\subsubsection{Constructor Term-Pattern (\texttt{Cons})}
Constructors match if they have the same name and kind
and the term-lists are of the same length and corresponding terms match.
$$
\inferrule
   { n_C = n_P
     \and
     \beta \vdash t_{C_i} :: t_{P_i} \leadsto \beta_i
   }
   {\beta \vdash \cc{n_C}{ts_C} :: \cc{n_P}{ts_P} \leadsto \uplus\{\beta_i\}}
   \quad
   \texttt{tMatch Cons}
$$
Here $ts_X = \langle t_{X_1}, t_{X_2}, \dots t_{X_n} \rangle$.
\begin{code}
tMatch' vts bind cbvs pbvs (Cons tkC nC tsC) (Cons tkP nP tsP)
 | tkC == tkP && nC == nP  =  tsMatch vts bind cbvs pbvs tsC tsP
\end{code}

\subsubsection{Binding Term-Pattern (\texttt{Bind})}

$$
\inferrule
   {n_C = n_P
    \and
    \beta;(B_C\cup vs_C,B_P\cup vs_P) \vdash t_C :: t_P \leadsto \beta'_t
    \and
    \beta \vdash vs_C :: vs_P \leadsto \beta'_{vs}
   }
   { \beta;(B_C,B_P) \vdash \bb{n_C}{vs_C}{t_C} :: \bb{n_P}{vs_P}{t_P}
     \leadsto
     \beta \uplus \beta'_t \uplus \beta'_{vs}
   }
   \quad
   \texttt{tMatch Binding}
$$
\begin{code}
tMatch' vts bind cbvs pbvs (Bind tkC nC vsC tC) (Bind tkP nP vsP tP)
  | tkP == tkC && nC == nP
    =  do let cbvs' = vsC `addBoundVarSet` cbvs
          let pbvs' = vsP `addBoundVarSet` pbvs
          bindT  <-  tMatch vts bind cbvs' pbvs' tC tP
          vsMatch vts bindT cbvs' pbvs' vsC vsP
\end{code}

\subsubsection{Lambda Term-Pattern (\texttt{Lam})}

$$
\inferrule
   {n_C = n_P
    \and
    \beta;(B_C\cup vs_C,B_P\cup vs_P) \vdash t_C :: t_P \leadsto \beta'_t
    \and
    \beta \vdash vl_C :: vl_P \leadsto \beta'_{vl}
   }
   { \beta;(B_C,B_P) \vdash \ll{n_C}{vl_C}{t_C} :: \ll{n_P}{vl_P}{t_P}
     \leadsto
     \beta \uplus \beta'_t \uplus \beta'_{vl}
   }
   \quad
   \texttt{tMatch Binding}
$$
\begin{code}
tMatch' vts bind cbvs pbvs (Lam tkC nC vlC tC) (Lam tkP nP vlP tP)
  | tkP == tkC && nC == nP
    =  do let cbvs' = vlC `addBoundVarList` cbvs
          let pbvs' = vlP `addBoundVarList` pbvs
          bindT  <-  tMatch vts bind cbvs' pbvs' tC tP
          vlMatch vts bindT cbvs' pbvs' vlC vlP
\end{code}


\subsubsection{Substitution Term-Pattern (\texttt{Sub})}

$$
\inferrule
   {n_C = n_P
    \and
    \beta \vdash t_C :: t_P \leadsto \beta'_t
    \and
    \beta \vdash \sigma_C :: \sigma_P \leadsto \beta'_\sigma
   }
   { \beta \vdash t_C\sigma_C :: t_P\sigma_P
     \leadsto
     \beta \uplus \beta'_t \uplus \beta'_\sigma
   }
   \quad
   \texttt{tMatch Subst}
$$
\begin{code}
tMatch' vts bind cbvs pbvs (Sub tkC tC subC) (Sub tkP tP subP)
  | tkP == tkC
    =  do bindT  <-  tMatch vts bind cbvs pbvs tC tP
          sMatch vts bindT cbvs pbvs subC subP
\end{code}


\subsubsection{Iterated Term-Pattern (\texttt{Iter})}

$$
\inferrule
   {na_C = na_P \land ni_C = ni_P
    \and
    \beta \vdash lvs_C :: lvs_P \leadsto \beta'
   }
   { \beta \vdash \ii{na_C}{ni_C}{lvs_C} :: \ii{na_P}{ni_P}{lvs_P}
     \leadsto
     \beta \uplus \beta\
   }
   \quad
   \texttt{tMatch Iter}
$$
Plus a more complicated rule !
\begin{code}
tMatch' vts bind cbvs pbvs (Iter tkC naC niC lvsC) (Iter tkP naP niP lvsP)
  | tkP == tkC && naC == naP && niC == niP
    =  error "\n\ttMatch Iter :: Iter N.Y.I."
tMatch' vts bind cbvs pbvs tC (Iter tkP naP niP lvsP)
  | tkP == termkind tC
    =  error "\n\ttMatch non-Iter :: Iter N.Y.I."
\end{code}

Any other case results in failure:
\begin{code}
tMatch' _ _ _ _ _ _  =  fail "tMatch: structural mismatch."
\end{code}

\subsection{Term-List Matching}

For now a simple zip-like walk along both lists
(no precomputing length to abort early).
\begin{code}
tsMatch :: MonadPlus mp
        => [VarTable] -> Binding -> CBVS -> PBVS
        -> [Candidate] -> [Pattern] -> mp Binding
tsMatch _ bind _ _ [] [] = return bind
tsMatch vts bind cbvs pvbs (tC:tsC) (tP:tsP)
 = do bind1 <- tMatch vts bind cbvs pvbs tC tP
      tsMatch vts bind1 cbvs pvbs tsC tsP
tsMatch _ _ _ _ _ _  =  fail "tsMatch: structural mismatch."
\end{code}

\newpage
\subsection{Term-Variable Matching}

We assume here that candidate term and pattern variable
had the same \texttt{TermKind}.
\begin{code}
tvMatch :: Monad m
       => [VarTable] -> Binding -> CBVS -> PBVS
       -> Candidate -> TermKind -> Variable -> m Binding
\end{code}

First, if the candidate is a variable
we go to do variable-on-variable matching:
\begin{code}
tvMatch vts bind cbvs pbvs (Var tkC vC) tkP vP
  = vMatch vts bind cbvs pbvs vC vP
\end{code}

Otherwise we check if the pattern is
bound, known, or arbitrary,
and act accordingly.
\begin{code}
tvMatch vts bind cbvs pvbs tC tkP vP@(Vbl _ vw _)
 | vw == VarV                 =  fail "tvMatch: var-variable cannot match term."
 | StdVar vP `S.member` pvbs  =  fail "tvMatch: bound pattern cannot match term."
 | vPmr /= UnknownVar         =  tkvMatch vts bind tC vPmr tkP vP
\end{code}
\subsubsection{Arbitrary Pattern Variable}
$$
\inferrule
   { v_P \notin B_P \cup \mathbf{dom}\,\kappa s}
   { \kappa s;\beta;B_P \vdash t_C :: v_P
    \leadsto
    \beta \uplus \{ v_P \mapsto t_C \}
  }
   \quad
   \texttt{tvMatch Arbitrary}
$$
\begin{code}
 | otherwise                  =  bindVarToTerm vP tC bind
 where
   vPmr = lookupVarTables vts vP
\end{code}

\newpage
\subsubsection{Known Pattern Variable}

\begin{code}
tkvMatch :: Monad m => [VarTable] -> Binding
       ->  Candidate -> VarMatchRole -> TermKind -> Variable -> m Binding
-- know vP is not in pbvs, in vts, and it maps to whatP
\end{code}
$$
\inferrule
   { v_P \notin B_P
     \and
     v_P \in \mathbf{dom}\,\kappa s
     \and
     t_C = V~v_C
     \and
     v_P = v_C
  }
   {\kappa s;\beta;B_P \vdash t_C :: v_P
   \leadsto
   \beta \uplus \{ v_P \mapsto v_P \}}
   \quad
   \texttt{tvMatch Known-Var-Refl}
$$
$$
\inferrule
   { v_P \notin B_P
     \and
     v_P \in \mathbf{dom}\,\kappa s
     \and
     t_C = V~v_C
     \and
     t_C = \kappa s(v_P)
  }
   {\kappa s;\beta;B_P \vdash t_C :: v_P
    \leadsto
    \beta \uplus \{ v_P \mapsto v_C \}}
   \quad
   \texttt{tvMatch Known-Var-Var}
$$
\begin{code}
-- know vP is not in pbvs, in vts, and it maps to whatP
tkvMatch vts bind tC@(Var _ vC) whatP tkP vP
 | vC == vP                                    =  bindVarToVar vP vP bind
 | isKnownConst whatP && tC == vmrConst whatP  =  bindVarToVar vP vC bind
\end{code}
$$
\inferrule
   { v_P \notin B_P
     \and
     v_P \in \mathbf{dom}\,\kappa s
     \and
     t_C \neq V~v_c
     \and
     t_C = \kappa s(v_P)
  }
   {\kappa s;\beta;B_P \vdash t_C :: v_P
    \leadsto
    \beta \uplus \{ v_P \mapsto t_C \}}
   \quad
   \texttt{tvMatch Known-Var-TVal}
$$
$$
\inferrule
   { v_P \notin B_P
     \and
     v_P \in \mathbf{dom}\,\kappa s
     \and
     t_C : T
     \and
     \kappa s(v_P) : T
  }
   {\kappa s;\beta;B_P \vdash t_C :: v_P
    \leadsto
    \beta \uplus \{ v_P \mapsto t_C \}}
   \quad
   \texttt{tvMatch Known-Var-TType}
$$
\begin{code}
-- know vP is not in pbvs, in vts, and it maps to whatP
tkvMatch vts bind tC whatP tkP vP
 | isKnownConst whatP && tC == vmrConst whatP     =  bindVarToTerm vP tC bind
 | isExprKind tkP && isKnownVar whatP
   && vmrType whatP == ekType tkP                 =  bindVarToTerm vP tC bind
tkvMatch _ _ _ _ _ _ = fail "tkvMatch: candidate not this known variable."
\end{code}

\newpage
\subsection{Variable Matching}

The rules regarding suitable matches for pattern variables
depend on what class of variable we have (\texttt{VarWhat})
and what we know about them (\texttt{VarMatchRole}).

First, rules based on classification:

\begin{tabular}{|c|c|c|}
\hline
Class & \texttt{VarWhat} & Allowed Candidates
\\\hline
 Observation & \texttt{ObsV} & Observation, Expression
\\\hline
 Variable & \texttt{VarV} & Variable
\\\hline
 Expression & \texttt{ExprV} & Expression
\\\hline
  Predicate & \texttt{PredV} & Predicate
\\\hline
\end{tabular}

Next, rules based on knowledge:

\begin{tabular}{|c|c|c|}
\hline
Knowledge & \texttt{VarMatchRole} & Allowed Candidates
\\\hline
Unknown & \texttt{UnknownVar} & Anything as per classification.
\\\hline
Known variable & \texttt{KnownVar} & Itself only
\\\hline
Known constant & \texttt{KnownConst} & Itself or the constant
\\\hline
\end{tabular}

Finally, rules based on the static or dynamic nature of known variables,
that do not apply if the variable is bound.
\begin{itemize}
  \item Static variables can match static or dynamic variables.
  \item Dynamic variables can only match those that have the
  same \texttt{VarWhen} value,
  except that the string in \texttt{During} may differ.
\end{itemize}
\begin{code}
whenCompVar :: Variable -> Variable -> Bool
whenCompVar (Vbl _ _ vkC) (Vbl _ _ vkP) = whenCompKind vkC vkP

whenCompKind :: VarKind -> VarKind -> Bool  -- candidate, pattern
whenCompKind _                    Static                =  True
whenCompKind (Dynamic Before)     (Dynamic Before)      =  True
whenCompKind (Dynamic (During _)) (Dynamic (During _))  =  True
whenCompKind (Dynamic After)      (Dynamic After)       =  True
whenCompKind _                    _                     =  False
\end{code}

Now, onto variable matching:

\begin{code}
vMatch :: Monad m
       => [VarTable] -> Binding -> CBVS -> PBVS
       -> Variable -> Variable
       -> m Binding
\end{code}

Observation pattern variables may match either
observation or expression variables,
while other variable classes may only match their own class.
\begin{code}
vMatch vts bind cbvs pvbs vC@(Vbl _ vwC _) vP@(Vbl _ vwP _)
 | StdVar vP `S.member` pvbs    =  bvMatch vts bind cbvs vC vP
 | vC == vP                     =  bindVarToVar vP vC bind
 | vwC == vwP                   =  vMatch' (lookupVarTables vts vP) vC vP
 | vwC == ExprV && vwP == ObsV  =  vMatch' (lookupVarTables vts vP) vC vP
 | otherwise                    =  fail "vMatch: class mismatch"
 where
\end{code}

Variable classes are compatible, but is the pattern ``known''?
\begin{code}
  -- vC /= vP
  vMatch' UnknownVar vC vP               =  bindVarToVar vP vC bind
  vMatch' (KnownVar typ) vC vP
    | whenCompVar vC vP                  =  bindVarToVar vP vC bind
  vMatch' (KnownConst (Var _ v)) vC vP
    | vC == v                            =  bindVarToVar vP vC bind
  vMatch' _ _ _  =  fail "vMatch: knowledge mismatch."
\end{code}

\subsubsection{Bound Pattern Variable}
$$
\inferrule
   { v_P \in B_P
      \and
     v_C \in B_C
   }
   {\beta;(B_C,B_P) \vdash v_C :: v_P
    \leadsto \beta \uplus \{ v_P \mapsto v_C \}}
   \quad
   \texttt{vMatch Bound-Var}
$$
In addition, both variables must have the same class.
\begin{code}
bvMatch :: Monad m => [VarTable] -> Binding -> CBVS
        -> Variable -> Variable -> m Binding
-- we know vP is in pbvs
bvMatch vts bind cbvs vC@(Vbl _ vwC _) vP@(Vbl _ vwP _)
 | vwC /= vwP  =  fail "bvMatch: variable class mismatch."
 | StdVar vC `S.member` cbvs  =  bindVarToVar vP vC bind
 | otherwise  =  fail "bvMatch: candidate not a bound variable."
\end{code}


\newpage
\subsection{Variable-List Matching}

\begin{code}
vlMatch :: MonadPlus mp => [VarTable] -> Binding -> CBVS -> PBVS
        -> VarList -> VarList -> mp Binding
\end{code}

Matching a non-empty candidate variable-list
against a non-empty pattern variable-list is non-trivial,
so we perform a number of phases.
The first phase tries to reconcile the pre-existing bindings
with the pattern variables.
If this succeeds,
we will have removed the already bound portions
from both variable lists,
resulting in a smaller ``freer'' problem.
This can then be solved in turn.
\begin{code}
-- vlC `subset` cbvs && vlP `subset` pbvc
vlMatch vts bind cbvs pbvs vlC vlP
  = do (vlC',vlP') <- applyBindingsToLists bind vlC vlP
       vlFreeMatch vts bind cbvs pbvs vlC' vlP'
\end{code}

\subsubsection{Applying Bindings to Lists}

We simply walk up the pattern looking for variables
already bound, and then search for what they are bound to, in the candidate
list.
We remove both, and continue.

We use tail-recursion and accumulate the un-bound (or ``free'') part of both
lists.
\begin{code}
applyBindingsToLists :: MonadPlus mp
                 => Binding -> VarList -> VarList -> mp (VarList,VarList)
applyBindingsToLists bind vlC vlP
  = applyBindingsToLists' bind [] [] vlC vlP

applyBindingsToLists' :: MonadPlus mp
                 => Binding
                 -> VarList -> VarList
                 -> VarList -> VarList -> mp (VarList,VarList)
\end{code}

Pattern list null: we are done, return the leftovers
\begin{code}
applyBindingsToLists' bind vlC' vlP' vlC []
  = return ((reverse vlC')++vlC, reverse vlP')
\end{code}

First pattern variable is standard:
\begin{code}
applyBindingsToLists' bind vlC' vlP' vlC (gP@(StdVar vP):vlP)
 = case lookupBind bind vP of
    Nothing           -> applyBindingsToLists' bind vlC' (gP:vlP') vlC vlP
    Just (BindTerm _) -> fail "vlMatch: pattern var already bound to term"
    Just (BindVar vB) -> findStdCandidate bind vlC' vlP' vlC vB vlP
\end{code}

First pattern variable is a list-variable:
\begin{code}
applyBindingsToLists' bind vlC' vlP' vlC (gP@(LstVar lvP):vlP)
 = case lookupLstBind bind lvP of
    Nothing  -> applyBindingsToLists' bind vlC' (gP:vlP') vlC vlP
    Just vlB -> findLstCandidate bind vlC' vlP' vlC vlB vlP
\end{code}


\paragraph{Find Standard Pattern-Variable Binding}
Found \texttt{vP} bound to \texttt{vB}.
Now need to search \texttt{vlC} for \texttt{vB}.
\begin{code}
findStdCandidate bind vlC' vlP' [] vB vlP
  = fail "vlMatch: std-pattern var's binding not in candidate list"
findStdCandidate bind vlC' vlP' (gC@(StdVar vC):vlC) vB vlP
 | vC == vB  = applyBindingsToLists' bind vlC' vlP' vlC vlP
 | otherwise = findStdCandidate bind (gC:vlC') vlP' vlC vB vlP
findStdCandidate bind vlC' vlP' (gC:vlC) vB vlP
  =  findStdCandidate bind (gC:vlC') vlP' vlC vB vlP
\end{code}

\paragraph{Find List Pattern-Variable Binding}
Found \texttt{vlP} bound to \texttt{vlB}.
Now need to search \texttt{vlC} for \texttt{vlB}.
\begin{code}
findLstCandidate bind vlC' vlP' vlC [] vlP
  = applyBindingsToLists' bind vlC' vlP' vlC vlP
findLstCandidate bind vlC' vlP' [] vlB vlP
  = fail "vlMatch: pattern list-var's binding not in candidate list"
findLstCandidate bind vlC' vlP' vlC@(gC:vlC_) vlB@(gB:vlB_) vlP
 | gC == gB && found
   = applyBindingsToLists' bind vlC' vlP' vlCrest vlP
 | otherwise = findLstCandidate bind (gC:vlC') vlP' vlC_ vlB vlP
 where
  (found,vlCrest) = vlB_ `pulledFrom` vlC_
\end{code}

\subsubsection{Free Variable-List Matching}

Here we are doing variable-list matching where all of the
pattern variables are free, \textit{i.e.}, not already in the binding.
We do not attempt a complete solutions,
as in fact there can be many possible bindings.
We adopt a heuristic that simply walks the pattern list
from left to right and tries to bind the head pattern variable
against some prefix of the candidate list.
\begin{code}
vlFreeMatch :: MonadPlus mp
              => [VarTable] -> Binding
              -> CBVS -> PBVS
              -> VarList -> VarList
              -> mp Binding
\end{code}

If both lists are empty, we are done:
\begin{code}
vlFreeMatch vts bind cbvs pbvs [] [] = return bind
\end{code}

If there are leftover candidate variables, we fail
\begin{code}
vlFreeMatch vts bind cbvs pbvs vlC []
  = fail "vlMatch: too many candidate variables."
\end{code}

If there are leftover pattern variables,
we suceed if they are all list-variables,
as they can be bound to the empty variable-list.
Otherwise we fail:
\begin{code}
vlFreeMatch vts bind cbvs pbvs [] (StdVar vP:_)
  = fail "vlMatch: too many std. pattern variables."
vlFreeMatch vts bind cbvs pbvs [] (LstVar lvP:vlP)
  = do bind' <- bindLVarToVList lvP [] bind
       vlFreeMatch vts bind' cbvs pbvs [] vlP
\end{code}

Standard pattern variable matches are easy.
The head of the candidate list must be a pattern variable.
It must also match according to the rules for variable matching.
\begin{code}
vlFreeMatch vts bind cbvs pbvs ((StdVar vC):vlC) ((StdVar vP):vlP)
  = do bind' <- vMatch vts bind cbvs pbvs vC vP
       vlFreeMatch vts bind' cbvs pbvs vlC vlP
vlFreeMatch vts bind cbvs pbvs vlC ((StdVar _):_)
  = fail "vlMatch: std pattern cannot match list candidate."
\end{code}


A pattern list-variable can match zero or more candidate general variables.
So here we come face-to-face with non-determinism.
For now we simply attempt to match by letting the list-variable
match the next $n$ candidate variables, for $n$ in the range $0\dots N$,
for some fixed $N$.
For now, we take $N=2$.
\begin{code}
vlFreeMatch vts bind cbvs pbvs vlC ((LstVar lvP):vlP)
  = vlFreeMatchN vts bind cbvs pbvs vlC lvP vlP 0
    `mplus`
    vlFreeMatchN vts bind cbvs pbvs vlC lvP vlP 1
    `mplus`
    vlFreeMatchN vts bind cbvs pbvs vlC lvP vlP 2
\end{code}

\begin{code}
vlFreeMatchN vts bind cbvs pbvs vlC lvP vlP n
 = do bind' <- bindLVarToVList lvP firstnC bind
      vlFreeMatch vts bind' cbvs pbvs restC vlP
 where (firstnC,restC) = splitAt n vlC
\end{code}

\newpage
\subsection{Variable-Set Matching}

We follow a similar pattern to variable-list matching.
First apply any bindings we have, and then try to match what is left.
The key difference here, obviously, is that order does not matter.
\begin{code}
vsMatch :: MonadPlus mp => [VarTable] -> Binding -> CBVS -> PBVS
        -> VarSet -> VarSet -> mp Binding
-- vsC `subset` cbvs && vsP `subset` pbvc
vsMatch vts bind cbvs pbvc vsC vsP
  = do (vsC',vsP') <- applyBindingsToSets bind vsC vsP
       vsFreeMatch vts bind cbvs pbvc vsC' vsP'
\end{code}

\subsubsection{Applying Bindings to Sets}

\begin{code}
applyBindingsToSets
  :: MonadPlus mp
  => Binding -> VarSet -> VarSet -> mp (VarSet,VarSet)
applyBindingsToSets bind vsC vsP
 = applyBindingsToSets' bind [] vsC $ S.toList vsP

applyBindingsToSets'
  :: MonadPlus mp
  => Binding -> VarList -> VarSet -> VarList -> mp (VarSet,VarSet)
\end{code}

Pattern list (set) empty, return the leftovers
\begin{code}
applyBindingsToSets' bind vlP' vsC [] = return (vsC,S.fromList vlP')
\end{code}

First pattern variable is standard:
\begin{code}
applyBindingsToSets' bind vlP' vsC (gP@(StdVar vP):vlP)
 = case lookupBind bind vP of
    Nothing -> applyBindingsToSets' bind (gP:vlP') vsC vlP
    Just (BindTerm _) -> fail "vsMatch: pattern var already bound to term."
    Just (BindVar vB)
     -> let gB = StdVar vB in
        if gB `S.member` vsC
        then applyBindingsToSets' bind vlP' (S.delete gB vsC) vlP
        else fail "vsMatch: std-pattern var's binding not in candidate set."
\end{code}

First pattern variable is a list-variable:
\begin{code}
applyBindingsToSets' bind vlP' vsC (gP@(LstVar lvP):vlP)
 = case lookupLstBind bind lvP of
    Nothing -> applyBindingsToSets' bind (gP:vlP') vsC vlP
    Just vlB
     -> let vsB = S.fromList vlB in
        if vsB `S.isSubsetOf` vsC
        then applyBindingsToSets' bind vlP' ((S.\\) vsC vsB) vlP
        else fail "vsMatch: pattern list-var's binding not in candidate set."
\end{code}

\subsubsection{Free Variable-Set Matching}

Here we are doing variable-set matching where all of the
pattern variables are free, \textit{i.e.}, not already in the binding.
We do not attempt a complete solution,
as in fact there can be many possible bindings.
\begin{code}
vsFreeMatch :: MonadPlus mp
              => [VarTable] -> Binding
              -> CBVS -> PBVS
              -> VarSet -> VarSet
              -> mp Binding
\end{code}

If one of both sets are empty then we can easily resolve matters,
\begin{code}
vsFreeMatch vts bind cbvs pbvs vsC vsP
 | S.null vsP  = if S.null vsC
                 then return bind
                 else fail "vsMatch: too many candidate variables."
 | S.null vsC  = if S.null $ S.filter isStdV vsP
                 then bindLVarSetToNull bind (S.toList vsP)
                 else fail "vsMatch: too many std. pattern variables."
\end{code}

If both sets are non-empty,
we have potentially non-deterministic outcomes.
First we try to pattern-match the standard variables.
Then we will attempt the list-variable matching.
\begin{code}
 | otherwise = vsFreeStdMatch vts bind cbvs pbvs vsC vsP
\end{code}

\begin{code}
bindLVarSetToNull bind [] = return bind
bindLVarSetToNull bind ((LstVar lv):vl)
 = do bind' <- bindLVarToVList lv [] bind
      bindLVarSetToNull bind' vl
bindLVarSetToNull _ (_:_) = fail "bindLVarSetToNull: std. variables not allowed."
\end{code}

First, pairing up very standard pattern variable
with one standard candidate variable,
if possible.
First we break down both sets into variables of the four various
temporal classifications
(static${}_s$, dynamic(before${}_b$, during${}_d$, after${}_a$)),
and check their sizes.
Let $p_s$, $p_b$, $p_d$, and $p_a$ denote the
number of standard pattern variables of each class,
and $c_s$, $c_b$, $c_d$, and $c_a$ denote similarly
for the standard candidate variables.
Given that each standard pattern must bind
to exactly one distinct candidate variable,
we get the following size constraints that must be satisfied:
\begin{eqnarray*}
   p_b \leq c_b && e_b = c_b - p_b
\\ p_d \leq c_d && e_d = c_d - p_d
\\ p_a \leq c_a && e_a = c_a - p_a
\\ p_s &\leq& c_s + e_b + e_d + e_a
\end{eqnarray*}

We first split the standard variables of both pattern and candidate sets,
check the inequalities above,
and then proceed to match the dynamics sets first,
followed by the static matching.
\begin{code}
vsFreeStdMatch vts bind cbvs pbvs vsC vsP
  | eb < 0  =  fail "vsMatch: too few std. candidate Before variables."
  | ed < 0  =  fail "vsMatch: too few std. candidate During variables."
  | ed < 0  =  fail "vsMatch: too few std. candidate After variables."
  | S.size vsPs > S.size vsCs + eb + ed + ea
            =  fail "vsMatch: too many std. pattern Static variables."
  | otherwise
    =  do (bindb,vsCb') <- vsFreeStdMatch' vts bind  cbvs pbvs vsCb vsPb
          (bindd,vsCd') <- vsFreeStdMatch' vts bindb cbvs pbvs vsCd vsPd
          (binda,vsCa') <- vsFreeStdMatch' vts bindd cbvs pbvs vsCa vsPa
          -- Static matches anything
          let vsCs' = S.unions [vsCs,vsCb',vsCd',vsCa']
          (binds,svsC') <- vsFreeStdMatch' vts bindd cbvs pbvs vsCs' vsPs
          vsFreeLstMatch vts binds cbvs pbvs (S.union lvsC svsC') lvsP
  where
    (lvsC,svsC) = S.partition isLstV vsC
    (lvsP,svsP) = S.partition isLstV vsP
    (vsCs,vsCb,vsCd,vsCa) = whenPartition svsC
    (vsPs,vsPb,vsPd,vsPa) = whenPartition svsP
    eb = S.size vsCb - S.size vsPb
    ed = S.size vsCd - S.size vsPd
    ea = S.size vsCa - S.size vsPa
\end{code}

This code, and its local definitions, may belong somewhere else.
\begin{code}
whenPartition :: VarSet -> (VarSet,VarSet,VarSet,VarSet)
whenPartition vs = (vsStatic,vsBefore,vsDuring,vsAfter)
 where
  isStatic gv  =  whenGVar gv == Static
  isBefore gv  =  whenGVar gv == Dynamic Before
  isAfter gv   =  whenGVar gv == Dynamic After
  isDuring gv  =  case whenGVar gv of
                    Dynamic (During _) -> True ; _ -> False
  (vsStatic,vs1)      =  S.partition isStatic vs
  (vsBefore,vs2)      =  S.partition isBefore vs1
  (vsDuring,vsAfter)  =  S.partition isDuring vs2
\end{code}

Matching $m$ pattern variables against $n$ candidate variables
allows for $n!/(m-n)!$ possible outcomes.
For now, we simply match variables in order
\begin{code}
-- all variables are standard, of the same temporality.
-- #vsC >= #vsP
vsFreeStdMatch' vts bind cbvs pbvs vsC vsP
 = do bind' <- zipVarVarBind bind vlC vlP
      return (bind',S.fromList vlC')
 where
   (vlC,vlC') = splitAt (S.size vsP) $ S.toList vsC ; vlP = S.toList vsP
\end{code}

\begin{code}
-- both lists should be  the same length
zipVarVarBind bind [] []  =  return bind
zipVarVarBind bind (gC:vlC) (gP:vlP)
 = do bind' <- bindGVarToGVar gP gC bind
      zipVarVarBind bind' vlC vlP
-- defensive programming
zipVarVarBind bind  _ []  =  return bind
zipVarVarBind bind []  _  =  return bind
\end{code}

We check for errors, and then just use \texttt{vlFreeMatch} for now.
\begin{code}
-- pattern is only list-variables.
vsFreeLstMatch vts bind cbvs pbvs vsC lvsP
 | null lvsP = if null vsC then return bind
               else fail "vsMatch: too many candidate variables."
 | otherwise  = vlFreeMatch vts bind cbvs pbvs (S.toList vsC) (S.toList lvsP)
\end{code}

\newpage
\subsection{Substitution Matching}

We match substitutions by first ignoring the replacement terms,
and doing a variable-set match on the variables.
We then use the new bindings to identify the corresponding terms,
and check that they match.
\begin{code}
sMatch vts bind cbvs pbvs (Substn tsC lvsC) (Substn tsP lvsP)
 = do bind'  <- vsMatch      vts  bind  cbvs pbvs vsC vsP
      bind'' <- tsMatchCheck vts  bind' cbvs pbvs tsC $ S.toList tsP
      lvsMatchCheck vts bind'' cbvs pbvs lvsC $ S.toList lvsP
 where
  vsC = S.map (StdVar . fst) tsC `S.union` S.map (LstVar . fst) lvsC
  vsP = S.map (StdVar . fst) tsP `S.union` S.map (LstVar . fst) lvsP
\end{code}

All the variable/term matches
\begin{code}
tsMatchCheck vts bind cbvs pbvs tsC []  =  return bind
tsMatchCheck vts bind cbvs pbvs tsC ((vP,tP):tsP)
 = do bind' <- vtMatchCheck vts bind cbvs pbvs tsC tP vP
      tsMatchCheck vts bind' cbvs pbvs tsC tsP

vtMatchCheck vts bind cbvs pbvs tsC tP vP
 = case lookupBind bind vP of
     Nothing            ->  fail "vsMatch: SHOULD NOT OCCUR!"
     Just (BindTerm _)  ->  fail "vsMatch: SHOULD NOT OCCUR!"
     Just (BindVar vB)
       ->  error "\n\t vtMatchCheck: NYFI\n"
\end{code}

All the list-var/list-var matches
\begin{code}
lvsMatchCheck vts bind cbvs pbvs lvsC lvsP
 = error "\n\t lvsMatchCheck: NYI\n"
\end{code}

\newpage
\subsection{Sub-Typing}

No surprises here.
\begin{code}
isSubTypeOf :: Type -> Type -> Bool
_ `isSubTypeOf` ArbType  =  True
ArbType `isSubTypeOf` _  =  False
_ `isSubTypeOf` (TypeVar _)  =  True
(TypeApp i1 ts1) `isSubTypeOf` (TypeApp i2 ts2)
 | i1 == i2  =  ts1 `areSubTypesOf` ts2
(DataType i1 fs1) `isSubTypeOf` (DataType i2 fs2)
 | i1 == i2  =  fs1 `areSubFieldsOf` fs2
(FunType tf1 ta1) `isSubTypeOf` (FunType tf2 ta2) -- tf contravariant !
   = tf2 `isSubTypeOf` tf1 && ta1 `isSubTypeOf` ta2
(GivenType i1) `isSubTypeOf` (GivenType i2)  = i1 == i2
_ `isSubTypeOf` _ = False
\end{code}

\begin{code}
areSubTypesOf :: [Type] -> [Type] -> Bool
[]       `areSubTypesOf` []        =  True
(t1:ts1) `areSubTypesOf` (t2:ts2)  =  t1 `isSubTypeOf` t2 && ts1 `areSubTypesOf` ts2
_        `areSubTypesOf` _         =  False
\end{code}

\begin{code}
areSubFieldsOf :: [(Identifier,[Type])] -> [(Identifier,[Type])] -> Bool
[] `areSubFieldsOf` []  =  True
((i1,ts1):fs1) `areSubFieldsOf` ((i2,ts2):fs2)
 | i1 == i2             =  ts1 `areSubTypesOf` ts2 && fs1 `areSubFieldsOf` fs2
_ `areSubFieldsOf` _    =  False
\end{code}
