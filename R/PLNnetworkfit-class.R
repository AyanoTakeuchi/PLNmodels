#' An R6 Class to represent a PLNfit in a sparse inverse covariance framework
#'
#' @description The function \code{\link{PLNnetwork}} produces a collection of models which are instances of object with class \code{PLNnetworkfit}.
#'
#' This class comes with a set of methods, some of them being useful for the user:
#' See the documentation for \code{\link[=plot_network]{plot_network}} + methods inherited from PLNfit.
#'
#' @field penalty the level of sparsity in the current model
#' @field model_par a list with the matrices associated with the estimated parameters of the pPCA model: Theta (covariates), Sigma (latent covariance) and Theta (latent precision matrix). Note Omega and Sigma are inverse of each other.
#' @field var_par a list with two matrices, M and S, which are the estimated parameters in the variational approximation
#' @field optim_par a list with parameters useful for monitoring the optimization
#' @field loglik variational lower bound of the loglikelihood
#' @field BIC variational lower bound of the BIC
#' @field ICL variational lower bound of the ICL
#' @field R_squared approximated goodness-of-fit criterion
#' @field degrees_freedom number of parameters in the current PLN model
#' @field criteria a vector with loglik, BIC, ICL, R_squared and degrees of freedom
#' @include PLNnetworkfit-class.R
#' @seealso The function \code{\link{PLNnetwork}}, the class \code{\link[=PLNnetworkfamily]{PLNnetworkfamily}}
PLNnetworkfit <-
  R6Class(classname = "PLNnetworkfit",
    inherit = PLNfit,
    public  = list(
      initialize = function(penalty=NA, Theta=NA, Sigma=NA, Omega=NA, M=NA, S=NA, J=NA, monitoring=list(objective = NA)) {
        super$initialize(Theta, Sigma, M, S, J, monitoring)
        private$lambda <- penalty
        private$Omega  <- Omega
      },
      update = function(penalty=NA, Theta=NA, Sigma=NA, Omega=NA, M=NA, S=NA, J=NA, R2=NA, monitoring=NA) {
        super$update(Theta, Sigma, M, S, J, R2, monitoring)
        if (!anyNA(penalty)) private$lambda <- penalty
        if (!anyNA(Omega))   private$Omega  <- Omega
      }
    ),
    private = list(
      Omega  = NA, # the p x p precision matrix
      lambda = NA  # the sparsity tuning parameter
    ),
    active = list(
      penalty         = function() {private$lambda},
      n_edges         = function() {sum(private$Omega[upper.tri(private$Omega, diag = FALSE)] != 0)},
      degrees_freedom = function() {self$p * self$d + self$n_edges},
      pen_loglik      = function() {self$loglik - private$lambda * sum(abs(private$Omega))},
      model_par = function() {
        par <- super$model_par
        par$Omega <- private$Omega
        par
      },
      EBIC      = function() {
        self$BIC - .5 * ifelse(self$n_edges > 0, self$n_edges * log(.5 * self$p*(self$p - 1)/self$n_edges), 0)
      },
      density   = function() {mean(self$latent_network("support"))},
      criteria  = function() {c(super$criteria, n_edges = self$n_edges, EBIC = self$EBIC, pen_loglik = self$pen_loglik, density = self$density)}
    )
)

## ----------------------------------------------------------------------
## PUBLIC METHODS FOR THE USERS
## ----------------------------------------------------------------------

#' @importFrom Matrix Matrix
PLNnetworkfit$set("public", "latent_network",
  function(type = c("partial_cor", "support", "precision")) {
    net <- switch(
      match.arg(type),
      "support"     = 1 * (private$Omega != 0 & !diag(TRUE, ncol(private$Omega))),
      "precision"   = private$Omega,
      "partial_cor" = {
        tmp <- -private$Omega / tcrossprod(sqrt(diag(private$Omega))); diag(tmp) <- 1
        tmp
        }
      )
    ## Enforce sparse Matrix encoding to avoid downstream problems with igraph::graph_from_adjacency_matrix
    ## as it fails when given dsyMatrix objects
    Matrix(net, sparse = TRUE)
  }
)

#' Plot the network (support of the inverse covariance) for a \code{PLNnetworkfit} object
#'
#' @name plot_network
#' @param plot logical. Should the plot be displayed or sent back as an igraph object
#' @param remove.isolated if \code{TRUE}, isolated node are remove before plotting.
#' @param layout an optional igraph layout
#' @return displays a graph (via igraph for small graph and corrplot for large ones) and/or sends back an igraph object
NULL
PLNnetworkfit$set("public", "plot_network",
  function(type = c("partial_cor", "support"), output = c("igraph", "corrplot"), edge.color = c("#F8766D", "#00BFC4"), remove.isolated = FALSE, node.labels = NULL, layout = layout_in_circle) {

    type <- match.arg(type)
    output <- match.arg(output)

    net <- self$latent_network(type)

    if (output == "igraph") {

      G <-  graph_from_adjacency_matrix(net, mode = "undirected", weighted = TRUE, diag = FALSE)

      if (!is.null(node.labels)) {
        igraph::V(G)$label <- node.labels
      } else {
        igraph::V(G)$label <- colnames(net)
      }
      ## Nice nodes
      V.deg <- degree(G)/sum(degree(G))
      igraph::V(G)$label.cex <- V.deg / max(V.deg) + .5
      igraph::V(G)$size <- V.deg * 100
      igraph::V(G)$label.color <- rgb(0, 0, .2, .8)
      igraph::V(G)$frame.color <- NA
      ## Nice edges
      igraph::E(G)$color <- ifelse(igraph::E(G)$weight > 0, edge.color[1], edge.color[2])
      if (type == "support")
        igraph::E(G)$width <- abs(igraph::E(G)$weight)
      else
        igraph::E(G)$width <- 15*abs(igraph::E(G)$weight)

      if (remove.isolated) {
        G <- delete.vertices(G, which(degree(G) == 0))
      }
      plot(G, layout = layout)
    }
    if (output == "corrplot") {
      if (ncol(net) > 100)
        colnames(net) <- rownames(net) <- rep(" ", ncol(net))
      G <- net
      diag(net) <- 0
      corrplot(as.matrix(net), method = "color", is.corr = FALSE, tl.pos = "td", cl.pos = "n", tl.cex = 0.5, type = "upper")
    }
    invisible(G)
})

PLNnetworkfit$set("public", "show",
function() {
  super$show(paste0("Poisson Lognormal with sparse inverse covariance (penalty = ", format(self$penalty,digits = 3),")\n"))
  cat("* Additional methods for network\n")
  cat("    $latent_network(), $plot_network()\n")
  cat("    $coefficient_path(), $density_path()\n")
})
