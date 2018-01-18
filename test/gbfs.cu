#define GRB_USE_APSPIE
#define private public

#include <iostream>
#include <algorithm>
#include <string>

#include <cstdio>
#include <cstdlib>

#include <cuda_profiler_api.h>

#include <boost/program_options.hpp>

#include "graphblas/graphblas.hpp"
#include "graphblas/algorithm/bfs.hpp"
#include "test/test.hpp"

bool debug_;
bool memory_;

int main( int argc, char** argv )
{
  std::vector<graphblas::Index> row_indices;
  std::vector<graphblas::Index> col_indices;
  std::vector<float> values;
  graphblas::Index nrows, ncols, nvals;

  // Parse arguments
  bool debug;
  bool transpose;
  bool mtxinfo;
  int  directed;
  int  niter;
  int  source;
  po::variables_map vm;

  // Read in sparse matrix
  if (argc < 2) {
    fprintf(stderr, "Usage: %s [matrix-market-filename]\n", argv[0]);
    exit(1);
  } else { 
    parseArgs( argc, argv, vm );
    debug     = vm["debug"    ].as<bool>();
    transpose = vm["transpose"].as<bool>();
    mtxinfo   = vm["mtxinfo"  ].as<bool>();
    directed  = vm["directed" ].as<int>();
    niter     = vm["niter"    ].as<int>();
    source    = vm["source"   ].as<int>();
    readMtx( argv[argc-1], row_indices, col_indices, values, nrows, ncols, 
        nvals, directed, mtxinfo );
  }

  // Matrix A
  graphblas::Matrix<float> a(nrows, ncols);
  CHECK( a.build(&row_indices, &col_indices, &values, nvals, GrB_NULL) );
  CHECK( a.nrows(&nrows) );
  CHECK( a.ncols(&ncols) );
  CHECK( a.nvals(&nvals) );
  if( debug ) CHECK( a.print() );

  // Vector v
  graphblas::Vector<float> v(nrows);

  // Descriptor desc
  graphblas::Descriptor desc;
  CHECK( desc.loadArgs(vm) );

  // Cpu BFS
  CpuTimer bfs_cpu;
  graphblas::Index* h_bfs_cpu = (graphblas::Index*)malloc(nrows*
      sizeof(graphblas::Index));
  int depth = 2000;
  bfs_cpu.Start();
  graphblas::algorithm::bfsCpu( source, &a, h_bfs_cpu, depth, transpose );
  bfs_cpu.Stop();

  // Warmup
  CpuTimer warmup;
  warmup.Start();
  graphblas::algorithm::bfs(&v, &a, source, &desc, transpose);
  warmup.Stop();

  std::vector<float> h_bfs_gpu;
  CHECK( v.extractTuples(&h_bfs_gpu, &nrows) );
  BOOST_ASSERT_LIST( h_bfs_cpu, h_bfs_gpu, nrows );
 
  CpuTimer vxm_gpu;
  cudaProfilerStart();
  vxm_gpu.Start();
  for( int i=0; i<niter; i++ )
  {
    graphblas::algorithm::bfs(&v, &a, source, &desc, transpose);
  }
  cudaProfilerStop();
  vxm_gpu.Stop();

  float flop = 0;
  std::cout << "cpu, " << bfs_cpu.ElapsedMillis() << ", \n";
  std::cout << "warmup, " << warmup.ElapsedMillis() << ", " <<
    flop/warmup.ElapsedMillis()/1000000.0 << "\n";
  float elapsed_vxm = vxm_gpu.ElapsedMillis();
  std::cout << "vxm, " << elapsed_vxm/niter << "\n";

  CHECK( v.extractTuples(&h_bfs_gpu, &nrows) );
  BOOST_ASSERT_LIST( h_bfs_cpu, h_bfs_gpu, nrows );

  return 0;
}
