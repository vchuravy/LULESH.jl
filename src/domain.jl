# access elements for comms
get_delv_xi(idx::IndexT, dom::AbstractDomain) = dom.d_delv_xi[idx]
get_delv_eta(idx::IndexT, dom::AbstractDomain) = dom.d_delv_eta[idx]
get_delv_zeta(idx::IndexT, dom::AbstractDomain) = dom.d_delv_zeta[idx]

get_x(idx::IndexT, dom::AbstractDomain) = dom.d_x[idx]
get_y(idx::IndexT, dom::AbstractDomain) = dom.d_y[idx]
get_z(idx::IndexT, dom::AbstractDomain) = dom.d_z[idx]

get_xd(idx::IndexT, dom::AbstractDomain) = dom.d_xd[idx]
get_yd(idx::IndexT, dom::AbstractDomain) = dom.d_yd[idx]
get_zd(idx::IndexT, dom::AbstractDomain) = dom.d_zd[idx]

get_fx(idx::IndexT, dom::AbstractDomain) = dom.d_fx[idx]
get_fy(idx::IndexT, dom::AbstractDomain) = dom.d_fy[idx]
get_fz(idx::IndexT, dom::AbstractDomain) = dom.d_fz[idx]

# assume communication to 6 neighbors by default
m_rowMin(domain::Domain) = (domain.m_rowLoc == 0)             ? false : true
m_rowMax(domain::Domain) = (domain.m_rowLoc == domain.m_tp-1) ? false : true
m_colMin(domain::Domain) = (domain.m_colLoc == 0)             ? false : true
m_colMax(domain::Domain) = (domain.m_colLoc == domain.m_tp-1) ? false : true
m_planeMin(domain::Domain) = (domain.m_planeLoc == 0)         ? false : true
m_planeMax(domain::Domain) = (domain.m_planeLoc == domain.m_tp-1) ? false : true

# host access
get_nodalMass(idx::IndexT, dom::AbstractDomain) = dom.h_nodalMass[idx]

colLoc(dom::AbstractDomain) = dom.m_colLoc
rowLoc(dom::AbstractDomain) = dom.m_rowLoc
planeLoc(dom::AbstractDomain) = dom.m_planeLoc
tp(dom::AbstractDomain) = dom.m_tp

function allocateNodalPersistent!(domain, domNodes)
    resize!(domain.x, domNodes)   # coordinates
    resize!(domain.y, domNodes)
    resize!(domain.z, domNodes)

    resize!(domain.xd, domNodes)  # velocities
    resize!(domain.yd, domNodes)
    resize!(domain.zd, domNodes)

    resize!(domain.xdd, domNodes) # accelerations
    resize!(domain.ydd, domNodes) # accelerations
    resize!(domain.zdd, domNodes) # accelerations

    resize!(domain.fx, domNodes)   # forces
    resize!(domain.fy, domNodes)
    resize!(domain.fz, domNodes)

     resize!(domain.dfx, domNodes)  # AD derivative of the forces
     resize!(domain.dfy, domNodes)
     resize!(domain.dfz, domNodes)

    resize!(domain.nodalMass, domNodes)  # mass
    return nothing
end

function allocateElemPersistent!(domain, domElems)
    resize!(domain.matElemlist, domElems) ;  # material indexset
    resize!(domain.nodelist, 8*domElems) ;   # elemToNode connectivity

    resize!(domain.lxim, domElems)  # elem connectivity through face g
    resize!(domain.lxip, domElems)
    resize!(domain.letam, domElems)
    resize!(domain.letap, domElems)
    resize!(domain.lzetam, domElems)
    resize!(domain.lzetap, domElems)

    resize!(domain.elemBC, domElems)   # elem face symm/free-surf flag g

    resize!(domain.e, domElems)    # energy g
    resize!(domain.p, domElems)    # pressure g

    resize!(domain.d_e, domElems)  # AD derivative of energy E g

    resize!(domain.q, domElems)    # q g
    resize!(domain.ql, domElems)   # linear term for q g
    resize!(domain.qq, domElems)   # quadratic term for q g
    resize!(domain.v, domElems)      # relative volume g

    resize!(domain.volo, domElems)   # reference volume g
    resize!(domain.delv, domElems)   # m_vnew - m_v g
    resize!(domain.vdov, domElems)   # volume derivative over volume g

    resize!(domain.arealg, domElems)   # elem characteristic length g

    resize!(domain.ss, domElems)       # "sound speed" g

    resize!(domain.elemMass, domElems)   # mass g
    return nothing
end

function initializeFields!(domain)
    # Basic Field Initialization

    fill!(domain.ss,0.0);
    fill!(domain.e,0.0)
    fill!(domain.p,0.0)
    fill!(domain.q,0.0)
    fill!(domain.v,1.0)

    fill!(domain.d_e,0.0)

    fill!(domain.xd,0.0)
    fill!(domain.yd,0.0)
    fill!(domain.zd,0.0)

    fill!(domain.xdd,0.0)
    fill!(domain.ydd,0.0)
    fill!(domain.zdd,0.0)

    fill!(domain.nodalMass,0.0)
end

function buildMesh!(domain, nx, edgeNodes, edgeElems, domNodes, domElems, x_h, y_h, z_h, nodelist_h)
    meshEdgeElems = domain.m_tp*nx ;

    resize!(x_h, domNodes)
    resize!(y_h, domNodes)
    resize!(z_h, domNodes)
    # initialize nodal coordinates
    # INDEXING
    nidx::IndexT = 1
    tz = 1.125*(domain.m_planeLoc*nx)/meshEdgeElems
    for plane in 1:edgeNodes
        ty = 1.125*(domain.m_rowLoc*nx)/meshEdgeElems
        for row in 1:edgeNodes
        tx = 1.125*(domain.m_colLoc*nx)/meshEdgeElems
            for col in 1:edgeNodes
                x_h[nidx] = tx
                y_h[nidx] = ty
                z_h[nidx] = tz
                nidx+=1
                # tx += ds ; // may accumulate roundoff...
                tx = 1.125*(domain.m_colLoc*nx+col+1)/meshEdgeElems
            end
        #// ty += ds ;  // may accumulate roundoff...
        ty = 1.125*(domain.m_rowLoc*nx+row+1)/meshEdgeElems
        end
        #// tz += ds ;  // may accumulate roundoff...
        tz = 1.125*(domain.m_planeLoc*nx+plane+1)/meshEdgeElems
    end

    copyto!(domain.x, x_h)
    copyto!(domain.y, y_h)
    copyto!(domain.z, z_h)
    @show domElems
    resize!(nodelist_h, domElems*8);

    # embed hexehedral elements in nodal point lattice
    # INDEXING
    zidx::IndexT = 0
    nidx = 1
    for plane in 1:edgeElems
        for row in 1:edgeElems
            for col in 1:edgeElems
                nodelist_h[8*zidx+1] = nidx
                nodelist_h[8*zidx+2] = nidx                                   + 1
                nodelist_h[8*zidx+3] = nidx                       + edgeNodes + 1
                nodelist_h[8*zidx+4] = nidx                       + edgeNodes
                nodelist_h[8*zidx+5] = nidx + edgeNodes*edgeNodes
                nodelist_h[8*zidx+6] = nidx + edgeNodes*edgeNodes             + 1
                nodelist_h[8*zidx+7] = nidx + edgeNodes*edgeNodes + edgeNodes + 1
                nodelist_h[8*zidx+8] = nidx + edgeNodes*edgeNodes + edgeNodes
                zidx+=1
                nidx+=1
            end
        nidx+=1
        end
    nidx+=edgeNodes
    end
    @show nodelist_h[2]
    @show edgeElems
    @show edgeNodes
    @show length(nodelist_h)
    @show minimum(nodelist_h)
    @show maximum(nodelist_h)
    copyto!(domain.nodelist, nodelist_h)
end

function setupConnectivityBC!(domain::Domain, edgeElems)
    domElems = domain.numElem;

    lxim_h = Vector{IndexT}(undef, domElems)
    lxip_h = Vector{IndexT}(undef, domElems)
    letam_h = Vector{IndexT}(undef, domElems)
    letap_h = Vector{IndexT}(undef, domElems)
    lzetam_h = Vector{IndexT}(undef, domElems)
    lzetap_h = Vector{IndexT}(undef, domElems)

    # set up elemement connectivity information
    lxim_h[1] = 0 ;
    for i in 2:domElems
       lxim_h[i]   = i-1
       lxip_h[i-1] = i
    end
    lxip_h[domElems-1] = domElems-1

    # INDEXING
    for i in 1:edgeElems
       letam_h[i] = i
       letap_h[domElems-edgeElems+i] = domElems-edgeElems+i
    end

    for i in edgeElems:domElems
       letam_h[i] = i-edgeElems
       letap_h[i-edgeElems+1] = i
    end

    for i in 1:edgeElems*edgeElems
       lzetam_h[i] = i
       lzetap_h[domElems-edgeElems*edgeElems+i] = domElems-edgeElems*edgeElems+i
    end

    for i in edgeElems*edgeElems:domElems
       lzetam_h[i] = i - edgeElems*edgeElems
       lzetap_h[i-edgeElems*edgeElems+1] = i
    end


    # set up boundary condition information
    elemBC_h = Vector{IndexT}(undef, domElems)
    for i in 1:domElems
        elemBC_h[i] = 0   # clear BCs by default
    end

    ghostIdx = [typemin(IndexT) for i in 1:6]::Vector{IndexT} # offsets to ghost locations

    pidx = domElems
    if m_planeMin(domain) != 0
        ghostIdx[1] = pidx
        pidx += domain.sizeX*domain.sizeY
    end

    if m_planeMax(domain) != 0
        ghostIdx[2] = pidx
        pidx += domain.sizeX*domain.sizeY
    end

    if m_rowMin(domain) != 0
        ghostIdx[3] = pidx
        pidx += domain.sizeX*domain.sizeZ
    end

    if m_rowMax(domain) != 0
        ghostIdx[4] = pidx
        pidx += domain.sizeX*domain.sizeZ
    end

    if m_colMin(domain) != 0
        ghostIdx[5] = pidx
        pidx += domain.sizeY*domain.sizeZ
    end

    if m_colMax(domain) != 0
        ghostIdx[6] = pidx
    end

    # symmetry plane or free surface BCs
    for i in 1:edgeElems
        planeInc = (i-1)*edgeElems*edgeElems
        rowInc   = (i-1)*edgeElems
        for j in 1:edgeElems
            if domain.m_planeLoc == 0
                elemBC_h[rowInc+j] |= ZETA_M_SYMM
            else
                elemBC_h[rowInc+j] |= ZETA_M_COMM
                lzetam_h[rowInc+j] = ghostIdx[0] + rowInc + j
            end

            if domain.m_planeLoc == domain.m_tp-1
                elemBC_h[rowInc+j+domElems-edgeElems*edgeElems] |= ZETA_P_FREE
            else
                elemBC_h[rowInc+j+domElems-edgeElems*edgeElems] |= ZETA_P_COMM
                lzetap_h[rowInc+j+domElems-edgeElems*edgeElems] = ghostIdx[1] + rowInc + j
            end

            if domain.m_rowLoc == 0
                elemBC_h[planeInc+j] |= ETA_M_SYMM
            else
                elemBC_h[planeInc+j] |= ETA_M_COMM
                letam_h[planeInc+j] = ghostIdx[2] + rowInc + j
            end

            if domain.m_rowLoc == domain.m_tp-1
                elemBC_h[planeInc+j+edgeElems*edgeElems-edgeElems] |= ETA_P_FREE
            else
                elemBC_h[planeInc+j+edgeElems*edgeElems-edgeElems] |= ETA_P_COMM
                letap_h[planeInc+j+edgeElems*edgeElems-edgeElems] = ghostIdx[3] +  rowInc + j
            end

            if domain.m_colLoc == 0
                elemBC_h[planeInc+j*edgeElems] |= XI_M_SYMM
            else
                elemBC_h[planeInc+j*edgeElems] |= XI_M_COMM
                lxim_h[planeInc+j*edgeElems] = ghostIdx[4] + rowInc + j
            end

            if domain.m_colLoc == domain.m_tp-1
                # FIXIT this goes out of bounds due to INDEXING
                # elemBC_h[planeInc+j*edgeElems+edgeElems-1] |= XI_P_FREE
            else
                elemBC_h[planeInc+j*edgeElems+edgeElems-1] |= XI_P_COMM
                lxip_h[planeInc+j*edgeElems+edgeElems-1] = ghostIdx[5] + rowInc + j
            end
        end
    end

    copyto!(domain.elemBC, elemBC_h)
    copyto!(domain.lxim, lxim_h)
    copyto!(domain.lxip, lxip_h)
    copyto!(domain.letam, letam_h)
    copyto!(domain.letap, letap_h)
    copyto!(domain.lzetam, lzetam_h)
    copyto!(domain.lzetap, lzetap_h)
end

function sortRegions(regReps_h::Vector{IndexT}, regSorted_h::Vector{IndexT}, regElemSize, numReg)
    regIndex = [v for v in 1:numReg]::Vector{IndexT}

    for i in 1:numReg-1
        for j in 1:numReg-i-1
            if regReps_h[j] < regReps_h[j+1]
                temp = regReps_h[j]
                regReps_h[j] = regReps_h[j+1]
                regReps_h[j+1] = temp

                temp = regElemSize[j]
                regElemSize[j] = regElemSize[j+1]
                regElemSize[j+1] = temp

                temp = regIndex[j]
                regIndex[j] = regIndex[j+1]
                regIndex[j+1] = temp
            end
        end
    end
    for i in 1:numReg
        regSorted_h[regIndex[i]] = i
    end
end

function createRegionIndexSets!(domain::Domain, nr::Int, b::Int, comm::Union{MPI.Comm, Nothing})
    domain.numReg = nr
    domain.balance = b
    @unpack_Domain domain
    myRank = getMyRank(comm)
    Random.seed!(myRank)

    regElemSize = Vector{Int}(undef, numReg)
    nextIndex::IndexT = 0

    regCSR_h = convert(Vector{Int}, regCSR) # records the begining and end of each region
    regReps_h = convert(Vector{Int}, regReps) # records the rep number per region
    regNumList_h = convert(Vector{IndexT}, regNumList) # Region number per domain element
    regElemlist_h = convert(Vector{IndexT}, regElemlist) # region indexset
    regSorted_h = convert(Vector{IndexT}, regSorted) # keeps index of sorted regions

    # if we only have one region just fill it
    # Fill out the regNumList with material numbers, which are always
    # the region index plus one
    if numReg == 1
        while nextIndex < numElem
            regNumList_h[nextIndex+1] = 1
            nextIndex+=1
        end
        regElemSize[1] = 0
    # If we have more than one region distribute the elements.
    else
        lastReg::Int = -1
        runto::IndexT = 0
        costDenominator::Int = 0
        regBinEnd = Vector{Int}(undef, numReg)
        # Determine the relative weights of all the regions.
        for i in 1:numReg
            regElemSize[i] = 0
            # INDEXING
            costDenominator += i^balance  # Total cost of all regions
            regBinEnd[i] = costDenominator  # Chance of hitting a given region is (regBinEnd[i] - regBinEdn[i-1])/costDenominator
        end
        # Until all elements are assigned
        while nextIndex < numElem
            # pick the region
            regionVar = rand(Int) % costDenominator
            i = 0
            # INDEXING
            while regionVar >= regBinEnd[i+1]
                i += 1
            end
            # rotate the regions based on MPI rank.  Rotation is Rank % NumRegions
            regionNum = ((i + myRank) % numReg) + 1
            # make sure we don't pick the same region twice in a row
            while regionNum == lastReg
                regionVar = rand(Int) % costDenominator
                i = 0
                while regionVar >= regBinEnd[i+1]
                    i += 1
                end
                regionNum = ((i + myRank) % numReg) + 1
            end
            # Pick the bin size of the region and determine the number of elements.
            binSize = rand(Int) % 1000
            if binSize < 773
                elements = rand(Int) % 15 + 1
            elseif binSize < 937
                elements = rand(Int) % 16 + 16
            elseif binSize < 970
                elements = rand(Int) % 32 + 32
            elseif binSize < 974
                elements = rand(Int) % 64 + 64
            elseif binSize < 978
                elements = rand(Int) % 128 + 128
            elseif binSize < 981
                elements = rand(Int) % 256 + 256
            else
                elements = rand(Int) % 1537 + 512
            end
            runto = elements + nextIndex
            # Store the elements.  If we hit the end before we run out of elements then just stop.
            while nextIndex < runto && nextIndex < numElem
                # INDEXING
                regNumList_h[nextIndex+1] = regionNum
                nextIndex += 1
            end
            lastReg = regionNum
        end
    end
    # Convert regNumList to region index sets
    # First, count size of each region
    for i in 1:numElem
        # INDEXING
        r = regNumList_h[i] # region index == regnum-1
        regElemSize[r]+=1
    end

    # Second, allocate each region index set
    for r in 1:numReg
        if r < div(numReg, 2)
            rep = 1
        elseif r < (numReg - div((numReg+15),20))
            rep = 1 + cost;
        else
            rep = 10 * (1 + cost)
        end
        regReps_h[r] = rep
    end
    sortRegions(regReps_h, regSorted_h, regElemSize, numReg);

    regCSR_h[1] = 0;
    # Second, allocate each region index set
    for i in 2:numReg
        regCSR_h[i] = regCSR_h[i-1] + regElemSize[i-1];
    end

    # Third, fill index sets
    for i in 1:numElem
        # INDEXING
        r = regSorted_h[regNumList_h[i]] # region index == regnum-1
        regElemlist_h[regCSR_h[r]+1] = i
        regCSR_h[r] += 1
    end

    # Copy to device
    copyto!(regCSR, regCSR_h) # records the begining and end of each region
    copyto!(regReps, regReps_h) # records the rep number per region
    copyto!(regNumList, regNumList_h) # Region number per domain element
    copyto!(regElemlist, regElemlist_h) # region indexset
    copyto!(regSorted, regSorted_h) # keeps index of sorted regions
    @unpack_Domain domain
end

function Domain(prob::LuleshProblem)
    VDF = prob.devicetype{prob.floattype}
    VDI = prob.devicetype{IndexT}
    VDInt = prob.devicetype{Int}
    numRanks = getNumRanks(prob.comm)
    colLoc = prob.col
    rowLoc = prob.row
    planeLoc = prob.plane
    nx = prob.nx
    tp = prob.side
    structured = prob.structured
    nr = prob.nr
    balance = prob.balance
    cost = prob.cost
    domain = Domain{prob.floattype}(
        0, nothing,
        VDI(), VDI(),
        VDI(), VDI(), VDI(), VDI(), VDI(), VDI(),
        VDInt(),
        VDF(), VDF(),
        VDF(),
        VDF(), VDF(), VDF(),
        VDF(),
        VDF(), VDF(), VDF(), # volo
        VDF(),
        VDF(),
        VDF(), # elemMass
        VDF(),
        VDF(), VDF(), VDF(),
        VDF(), VDF(), VDF(),
        VDF(), VDF(), VDF(),
        VDF(), VDF(), VDF(),
        VDF(), VDF(), VDF(),
        VDF(), VDF(), VDF(),
        VDF(), VDF(), VDF(),
        VDF(), VDF(), VDF(),
        # FIXIT This is wrong
        VDF(), Vector{prob.floattype}(),
        VDI(), VDI(), VDI(),
        VDInt(), VDInt(), VDI(),
        0.0, 0.0, 0.0, 0.0, 0.0, 0,
        0.0, 0.0, 0.0, 0.0, 0, 0,
        0.0, 0.0,
        0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        0,0,0,0,0,0,0,0,0,
        0,
        0,
        0,0,0,
        0,
        0,0,0, Vector{Int}(), VDInt(), VDInt(), VDI(), VDI(), VDI()

    )

    domain.max_streams = 32
    # domain->streams.resize(domain->max_streams);
    # TODO: CUDA stream stuff goes here
    domain.streams = nothing

# #   for (Int_t i=0;i<domain->max_streams;i++)
# #     cudaStreamCreate(&(domain->streams[i]));

# #   cudaEventCreateWithFlags(&domain->time_constraint_computed,cudaEventDisableTiming);

#   Index_t domElems;
#   Index_t domNodes;
#   Index_t padded_domElems;

    nodelist_h = Vector{IndexT}()
    x_h = Vector{prob.floattype}()
    y_h = Vector{prob.floattype}()
    z_h = Vector{prob.floattype}()

    if structured

        domain.m_tp       = tp
        # domain.m_numRanks = numRanks

        domain.m_colLoc   =   colLoc
        domain.m_rowLoc   =   rowLoc
        domain.m_planeLoc = planeLoc

        edgeElems = nx
        edgeNodes = edgeElems+1

        domain.sizeX = edgeElems
        domain.sizeY = edgeElems
        domain.sizeZ = edgeElems

        domain.numElem = domain.sizeX*domain.sizeY*domain.sizeZ ;
        # domain.padded_numElem = PAD(domain.numElem,32);

        domain.numNode = (domain.sizeX+1)*(domain.sizeY+1)*(domain.sizeZ+1)
        # domain.padded_numNode = PAD(domain.numNode,32);

        domElems = domain.numElem
        domNodes = domain.numNode
        # padded_domElems = domain.padded_numElem

        # Build domain object here. Not nice.


        allocateElemPersistent!(domain, domElems);
        allocateNodalPersistent!(domain, domNodes);

    #     domain->SetupCommBuffers(edgeNodes);

        initializeFields!(domain)

        buildMesh!(domain, nx, edgeNodes, edgeElems, domNodes, domElems, x_h, y_h, z_h, nodelist_h)

        domain.numSymmX = domain.numSymmY = domain.numSymmZ = 0

        if domain.m_colLoc == 0
            domain.numSymmX = (edgeElems+1)*(edgeElems+1)
        end
        if domain.m_rowLoc == 0
            domain.numSymmY = (edgeElems+1)*(edgeElems+1)
        end
        if domain.m_planeLoc == 0
            domain.numSymmZ = (edgeElems+1)*(edgeElems+1)
        end
        resize!(domain.symmX, edgeNodes*edgeNodes)
        resize!(domain.symmY, edgeNodes*edgeNodes)
        resize!(domain.symmZ, edgeNodes*edgeNodes)

        # Set up symmetry nodesets

        symmX_h = convert(Vector, domain.symmX)
        symmY_h = convert(Vector, domain.symmY)
        symmZ_h = convert(Vector, domain.symmZ)

        nidx = 1
        # INDEXING
        for i in 1:edgeNodes
            planeInc = (i-1)*edgeNodes*edgeNodes
            rowInc   = (i-1)*edgeNodes
            for j in 1:edgeNodes
                if domain.m_planeLoc == 0
                    symmZ_h[nidx] = rowInc   + j
                end
                if domain.m_rowLoc == 0
                    symmY_h[nidx] = planeInc + j
                end
                if domain.m_colLoc == 0
                    symmX_h[nidx] = planeInc + j*edgeNodes
                end
                nidx+=1
            end
        end
        if domain.m_planeLoc == 0
            domain.symmZ = symmZ_h
        end
        if domain.m_rowLoc == 0
            domain.symmY = symmY_h
        end
        if domain.m_colLoc == 0
            domain.symmX = symmX_h
        end

        setupConnectivityBC!(domain, edgeElems)
    else
        error("Reading unstructured mesh is currently missing in the Julia version of LULESH.")
    end
    # set up node-centered indexing of elements */
    nodeElemCount_h = zeros(IndexT, domNodes)
    # INDEXING
    for i in 1:domElems
        for j in 0:7
            nodeElemCount_h[nodelist_h[j*domElems+i]]+=1
        end
    end

    nodeElemStart_h = zeros(IndexT, domNodes)
    nodeElemStart_h[1] = 0
    for i in 2:domNodes
        nodeElemStart_h[i] = nodeElemStart_h[i-1] + nodeElemCount_h[i-1]
    end
    nodeElemCornerList_h = Vector{IndexT}(undef, nodeElemStart_h[domNodes] + nodeElemCount_h[domNodes] )

    nodeElemCount_h .= 0

    for j in 0:7
        for i in 1:domElems
            m = nodelist_h[domElems*j+i]
            k = domElems*j + i
            # INDEXING
            offset = nodeElemStart_h[m] + nodeElemCount_h[m]
            nodeElemCornerList_h[offset+1] = k
            nodeElemCount_h[m] += 1
        end
    end

    clSize = nodeElemStart_h[domNodes] + nodeElemCount_h[domNodes]
    for i in 1:clSize
        clv = nodeElemCornerList_h[i] ;
        if (clv < 0) || (clv > domElems*8)
            error("AllocateNodeElemIndexes(): nodeElemCornerList entry out of range!")
        end
    end

    domain.nodeElemStart = convert(VDI, nodeElemStart_h)
    domain.nodeElemCount = convert(VDI, nodeElemCount_h)
    domain.nodeElemCornerList = convert(VDI, nodeElemCornerList_h)

    # Create a material IndexSet (entire domain same material for now)
    matElemlist_h = Vector{IndexT}(undef, domElems)
    for i in 1:domElems
        matElemlist_h[i] = i
    end
    copyto!(domain.matElemlist, matElemlist_h)

    # TODO Not sure what to do here
    #   cudaMallocHost(&domain->dtcourant_h,sizeof(Real_t),0);
    #   cudaMallocHost(&domain->dthydro_h,sizeof(Real_t),0);
    #   cudaMallocHost(&domain->bad_vol_h,sizeof(Index_t),0);
    #   cudaMallocHost(&domain->bad_q_h,sizeof(Index_t),0);


    domain.bad_vol_h = -1
    domain.bad_q_h = -1
    domain.dthydro_h = 1e20
    domain.dtcourant_h = 1e20

    # initialize material parameters
    domain.time_h      = 0.
    domain.dtfixed = -1.0e-6
    domain.deltatimemultlb = 1.1
    domain.deltatimemultub = 1.2
    domain.stoptime  = 1.0e-2
    domain.dtmax     = 1.0e-2
    domain.cycle   = 0

    domain.e_cut = 1.0e-7
    domain.p_cut = 1.0e-7
    domain.q_cut = 1.0e-7
    domain.u_cut = 1.0e-7
    domain.v_cut = 1.0e-10

    domain.hgcoef      = 3.0
    domain.ss4o3       = 4.0/3.0

    domain.qstop              =  1.0e+12
    domain.monoq_max_slope    =  1.0
    domain.monoq_limiter_mult =  2.0
    domain.qlc_monoq          = 0.5
    domain.qqc_monoq          = 2.0/3.0
    domain.qqc                = 2.0

    domain.pmin =  0.
    domain.emin = -1.0e+15

    domain.dvovmax =  0.1

    domain.eosvmax =  1.0e+9
    domain.eosvmin =  1.0e-9

    domain.refdens =  1.0

    # initialize field data
    nodalMass_h = Vector{prob.floattype}(undef, domNodes)
    volo_h = Vector{prob.floattype}(undef, domElems)
    elemMass_h = Vector{prob.floattype}(undef, domElems)

    for i in 1:domElems
        x_local = Vector{prob.floattype}(undef, 8)
        y_local = Vector{prob.floattype}(undef, 8)
        z_local = Vector{prob.floattype}(undef, 8)
        for lnode in 0:7
            gnode = nodelist_h[lnode*domElems+i]
            x_local[lnode+1] = x_h[gnode]
            y_local[lnode+1] = y_h[gnode]
            z_local[lnode+1] = z_h[gnode]
        end
        # volume calculations
        volume = calcElemVolume(x_local, y_local, z_local )
        volo_h[i] = volume
        elemMass_h[i] = volume
        for j in 0:7
            gnode = nodelist_h[j*domElems+i]
            nodalMass_h[gnode] += volume / 8.0
        end
    end

    copyto!(domain.nodalMass, nodalMass_h)
    copyto!(domain.volo, volo_h)
    copyto!(domain.elemMass, elemMass_h)

    # deposit energy
    domain.octantCorner = 0;
    # deposit initial energy
    # An energy of 3.948746e+7 is correct for a problem with
    # 45 zones along a side - we need to scale it
    ebase = 3.948746e+7
    scale = (nx*domain.m_tp)/45.0;
    einit = ebase*scale*scale*scale;
    if domain.m_rowLoc + domain.m_colLoc + domain.m_planeLoc == 0
        # Dump into the first zone (which we know is in the corner)
        # of the domain that sits at the origin
        # TODO This only works for CUDA
        CUDA.@allowscalar domain.e[1] = einit;
    end

    # set initial deltatime base on analytic CFL calculation
    CUDA.@allowscalar domain.deltatime_h = (.5*cbrt(domain.volo[1]))/sqrt(2*einit);

    domain.cost = cost
    resize!(domain.regNumList, domain.numElem)  # material indexset
    resize!(domain.regElemlist, domain.numElem)  # material indexset
    resize!(domain.regCSR, nr)
    resize!(domain.regReps, nr)
    resize!(domain.regSorted, nr)

    # Setup region index sets. For now, these are constant sized
    # throughout the run, but could be changed every cycle to
    # simulate effects of ALE on the lagrange solver

    createRegionIndexSets!(domain, nr, balance, prob.comm);
    return domain
end

function initStressTermsForElems(domain::Domain, sigxx, sigyy, sigzz)
    # Based on FORTRAN implementation down from here
    sigxx .=  .- domain.p .- domain.q
    sigyy .=  .- domain.p .- domain.q
    sigzz .=  .- domain.p .- domain.q
end

function calcElemShapeFunctionDerivatives(x, y, z, b, el_volume, k)

  x0 = x[1]
  x1 = x[2]
  x2 = x[3]
  x3 = x[4]
  x4 = x[5]
  x5 = x[6]
  x6 = x[7]
  x7 = x[8]

  y0 = y[1]
  y1 = y[2]
  y2 = y[3]
  y3 = y[4]
  y4 = y[5]
  y5 = y[6]
  y6 = y[7]
  y7 = y[8]

  z0 = z[1]
  z1 = z[2]
  z2 = z[3]
  z3 = z[4]
  z4 = z[5]
  z5 = z[6]
  z6 = z[7]
  z7 = z[8]

  fjxxi = .125 * ( (x6-x0) + (x5-x3) - (x7-x1) - (x4-x2) )
  fjxet = .125 * ( (x6-x0) - (x5-x3) + (x7-x1) - (x4-x2) )
  fjxze = .125 * ( (x6-x0) + (x5-x3) + (x7-x1) + (x4-x2) )

  fjyxi = .125 * ( (y6-y0) + (y5-y3) - (y7-y1) - (y4-y2) )
  fjyet = .125 * ( (y6-y0) - (y5-y3) + (y7-y1) - (y4-y2) )
  fjyze = .125 * ( (y6-y0) + (y5-y3) + (y7-y1) + (y4-y2) )

  fjzxi = .125 * ( (z6-z0) + (z5-z3) - (z7-z1) - (z4-z2) )
  fjzet = .125 * ( (z6-z0) - (z5-z3) + (z7-z1) - (z4-z2) )
  fjzze = .125 * ( (z6-z0) + (z5-z3) + (z7-z1) + (z4-z2) )

  # compute cofactors
  cjxxi =    (fjyet * fjzze) - (fjzet * fjyze)
  cjxet =  - (fjyxi * fjzze) + (fjzxi * fjyze)
  cjxze =    (fjyxi * fjzet) - (fjzxi * fjyet)

  cjyxi =  - (fjxet * fjzze) + (fjzet * fjxze)
  cjyet =    (fjxxi * fjzze) - (fjzxi * fjxze)
  cjyze =  - (fjxxi * fjzet) + (fjzxi * fjxet)

  cjzxi =    (fjxet * fjyze) - (fjyet * fjxze)
  cjzet =  - (fjxxi * fjyze) + (fjyxi * fjxze)
  cjzze =    (fjxxi * fjyet) - (fjyxi * fjxet)

  # calculate partials :
  #     this need only be done for l = 0,1,2,3   since , by symmetry ,
  #     (6,7,4,5) = - (0,1,2,3) .
  b[1,1] =   -  cjxxi  -  cjxet  -  cjxze
  b[2,1] =      cjxxi  -  cjxet  -  cjxze
  b[3,1] =      cjxxi  +  cjxet  -  cjxze
  b[4,1] =   -  cjxxi  +  cjxet  -  cjxze
  b[5,1] = -b[3,1]
  b[6,1] = -b[4,1]
  b[7,1] = -b[1,1]
  b[8,1] = -b[2,1]

  b[1,2] =   -  cjyxi  -  cjyet  -  cjyze
  b[2,2] =      cjyxi  -  cjyet  -  cjyze
  b[3,2] =      cjyxi  +  cjyet  -  cjyze
  b[4,2] =   -  cjyxi  +  cjyet  -  cjyze
  b[5,2] = -b[3,2]
  b[6,2] = -b[4,2]
  b[7,2] = -b[1,2]
  b[8,2] = -b[2,2]

  b[1,3] =   -  cjzxi  -  cjzet  -  cjzze
  b[2,3] =      cjzxi  -  cjzet  -  cjzze
  b[3,3] =      cjzxi  +  cjzet  -  cjzze
  b[4,3] =   -  cjzxi  +  cjzet  -  cjzze
  b[5,3] = -b[3,3]
  b[6,3] = -b[4,3]
  b[7,3] = -b[1,3]
  b[8,3] = -b[2,3]

  # calculate jacobian determinant (volume)
  el_volume[k] = 8.0 * ( fjxet * cjxet + fjyet * cjyet + fjzet * cjzet)
end

function sumElemFaceNormal(normalX0, normalY0, normalZ0,
                             normalX1, normalY1, normalZ1,
                             normalX2, normalY2, normalZ2,
                             normalX3, normalY3, normalZ3,
                              x0,  y0,  z0,
                              x1,  y1,  z1,
                              x2,  y2,  z2,
                              x3,  y3,  z3     )


  RHALF = 0.5
  RQTR = 0.25

  bisectX0 = RHALF * (x3 + x2 - x1 - x0)
  bisectY0 = RHALF * (y3 + y2 - y1 - y0)
  bisectZ0 = RHALF * (z3 + z2 - z1 - z0)
  bisectX1 = RHALF * (x2 + x1 - x3 - x0)
  bisectY1 = RHALF * (y2 + y1 - y3 - y0)
  bisectZ1 = RHALF * (z2 + z1 - z3 - z0)
  areaX = RQTR * (bisectY0 * bisectZ1 - bisectZ0 * bisectY1)
  areaY = RQTR * (bisectZ0 * bisectX1 - bisectX0 * bisectZ1)
  areaZ = RQTR * (bisectX0 * bisectY1 - bisectY0 * bisectX1)

  normalX0 = normalX0 + areaX
  normalX1 = normalX1 + areaX
  normalX2 = normalX2 + areaX
  normalX3 = normalX3 + areaX

  normalY0 = normalY0 + areaY
  normalY1 = normalY1 + areaY
  normalY2 = normalY2 + areaY
  normalY3 = normalY3 + areaY

  normalZ0 = normalZ0 + areaZ
  normalZ1 = normalZ1 + areaZ
  normalZ2 = normalZ2 + areaZ
  normalZ3 = normalZ3 + areaZ
end


function calcElemNodeNormals(pf, x, y, z)

    pfx = @view pf[:,1]
    pfy = @view pf[:,2]
    pfz = @view pf[:,3]

    pfx .= 0.0
    pfy .= 0.0
    pfz .= 0.0

    # evaluate face one: nodes 1, 2, 3, 4
    sumElemFaceNormal(pfx[1], pfy[1], pfz[1],
                            pfx[2], pfy[2], pfz[2],
                            pfx[3], pfy[3], pfz[3],
                            pfx[4], pfy[4], pfz[4],
                            x[1], y[1], z[1], x[2], y[2], z[2],
                            x[3], y[3], z[3], x[4], y[4], z[4])
    # evaluate face two: nodes 1, 5, 6, 2
    sumElemFaceNormal(pfx[1], pfy[1], pfz[1],
                            pfx[5], pfy[5], pfz[5],
                            pfx[6], pfy[6], pfz[6],
                            pfx[2], pfy[2], pfz[2],
                            x[1], y[1], z[1], x[5], y[5], z[5],
                            x[6], y[6], z[6], x[2], y[2], z[2])
    #evaluate face three: nodes 2, 6, 7, 3
    sumElemFaceNormal(pfx[2], pfy[2], pfz[2],
                            pfx[6], pfy[6], pfz[6],
                            pfx[7], pfy[7], pfz[7],
                            pfx[3], pfy[3], pfz[3],
                            x[2], y[2], z[2], x[6], y[6], z[6],
                            x[7], y[7], z[7], x[3], y[3], z[3])
    #evaluate face four: nodes 3, 7, 8, 4
    sumElemFaceNormal(pfx[3], pfy[3], pfz[3],
                            pfx[7], pfy[7], pfz[7],
                            pfx[8], pfy[8], pfz[8],
                            pfx[4], pfy[4], pfz[4],
                            x[3], y[3], z[3], x[7], y[7], z[7],
                            x[8], y[8], z[8], x[4], y[4], z[4])
    # evaluate face five: nodes 4, 8, 5, 1
    sumElemFaceNormal(pfx[4], pfy[4], pfz[4],
                            pfx[8], pfy[8], pfz[8],
                            pfx[5], pfy[5], pfz[5],
                            pfx[1], pfy[1], pfz[1],
                            x[4], y[4], z[4], x[8], y[8], z[8],
                            x[5], y[5], z[5], x[1], y[1], z[1])
    # evaluate face six: nodes 5, 8, 7, 6
    sumElemFaceNormal(pfx[5], pfy[5], pfz[5],
                            pfx[8], pfy[8], pfz[8],
                            pfx[7], pfy[7], pfz[7],
                            pfx[6], pfy[6], pfz[6],
                            x[5], y[5], z[5], x[8], y[8], z[8],
                            x[7], y[7], z[7], x[6], y[6], z[6])
end

function sumElemStressesToNodeForces(B, sig_xx, sig_yy, sig_zz,  fx_elem,  fy_elem,  fz_elem, k)

  fx = @view fx_elem[(k-1)*8+1:k*8]
  fy = @view fy_elem[(k-1)*8+1:k*8]
  fz = @view fz_elem[(k-1)*8+1:k*8]
  stress_xx = sig_xx[k]
  stress_yy = sig_yy[k]
  stress_zz = sig_zz[k]

  pfx0 = B[1,1]
  pfx1 = B[2,1]
  pfx2 = B[3,1]
  pfx3 = B[4,1]
  pfx4 = B[5,1]
  pfx5 = B[6,1]
  pfx6 = B[7,1]
  pfx7 = B[8,1]

  pfy0 = B[1,2]
  pfy1 = B[2,2]
  pfy2 = B[3,2]
  pfy3 = B[4,2]
  pfy4 = B[5,2]
  pfy5 = B[6,2]
  pfy6 = B[7,2]
  pfy7 = B[8,2]

  pfz0 = B[1,3]
  pfz1 = B[2,3]
  pfz2 = B[3,3]
  pfz3 = B[4,3]
  pfz4 = B[5,3]
  pfz5 = B[6,3]
  pfz6 = B[7,3]
  pfz7 = B[8,3]

  fx[1] = -( stress_xx * pfx0 )
  fx[2] = -( stress_xx * pfx1 )
  fx[3] = -( stress_xx * pfx2 )
  fx[4] = -( stress_xx * pfx3 )
  fx[5] = -( stress_xx * pfx4 )
  fx[6] = -( stress_xx * pfx5 )
  fx[7] = -( stress_xx * pfx6 )
  fx[8] = -( stress_xx * pfx7 )

  fy[1] = -( stress_yy * pfy0  )
  fy[2] = -( stress_yy * pfy1  )
  fy[3] = -( stress_yy * pfy2  )
  fy[4] = -( stress_yy * pfy3  )
  fy[5] = -( stress_yy * pfy4  )
  fy[6] = -( stress_yy * pfy5  )
  fy[7] = -( stress_yy * pfy6  )
  fy[8] = -( stress_yy * pfy7  )

  fz[1] = -( stress_zz * pfz0 )
  fz[2] = -( stress_zz * pfz1 )
  fz[3] = -( stress_zz * pfz2 )
  fz[4] = -( stress_zz * pfz3 )
  fz[5] = -( stress_zz * pfz4 )
  fz[6] = -( stress_zz * pfz5 )
  fz[7] = -( stress_zz * pfz6 )
  fz[8] = -( stress_zz * pfz7 )
end


function integrateStressForElems(domain::Domain, sigxx, sigyy, sigzz, determ)
    # Based on FORTRAN implementation down from here
    # loop over all elements
    numElem8 = domain.numElem*8
    T = typeof(domain.x)
    x_local = T(undef, 8)
    y_local = T(undef, 8)
    z_local = T(undef, 8)
    fx_elem = T(undef, numElem8)
    fy_elem = T(undef, numElem8)
    fz_elem = T(undef, numElem8)
    # FIXIT. This has to be device type
    B = Matrix(undef, 8, 3)
    for k in 1:domain.numElem
        for lnode in 1:8
            # INDEXING
            gnode = domain.nodelist[lnode + (k-1)*8]
            x_local[lnode] = domain.x[gnode]
            y_local[lnode] = domain.y[gnode]
            z_local[lnode] = domain.z[gnode]
        end
        calcElemShapeFunctionDerivatives(x_local, y_local, z_local, B, determ, k)
        calcElemNodeNormals(B, x_local, y_local, z_local)
        sumElemStressesToNodeForces(B, sigxx, sigyy, sigzz, fx_elem, fy_elem, fz_elem, k)
    end

    numNode = domain.numNode

    for gnode in 1:numNode
        count = domain.nodeElemCount[gnode]
        start = domain.nodeElemStart[gnode]
        fx = 0.0
        fy = 0.0
        fz = 0.0
        for i in 1:count
            elem = domain.nodeElemCornerList[start+i]
            fx = fx + fx_elem[elem]
            fy = fy + fy_elem[elem]
            fz = fz + fz_elem[elem]
        end
        domain.fx[gnode] = fx
        domain.fy[gnode] = fy
        domain.fz[gnode] = fz
    end
end

function collectDomainNodesToElemNodes(domain::Domain, elemX, elemY, elemZ, i)

    nd0i = domain.nodelist[i]
    nd1i = domain.nodelist[i+1]
    nd2i = domain.nodelist[i+2]
    nd3i = domain.nodelist[i+3]
    nd4i = domain.nodelist[i+4]
    nd5i = domain.nodelist[i+5]
    nd6i = domain.nodelist[i+6]
    nd7i = domain.nodelist[i+7]

    elemX[1] = domain.x[nd0i]
    elemX[2] = domain.x[nd1i]
    elemX[3] = domain.x[nd2i]
    elemX[4] = domain.x[nd3i]
    elemX[5] = domain.x[nd4i]
    elemX[6] = domain.x[nd5i]
    elemX[7] = domain.x[nd6i]
    elemX[8] = domain.x[nd7i]

    elemY[1] = domain.y[nd0i]
    elemY[2] = domain.y[nd1i]
    elemY[3] = domain.y[nd2i]
    elemY[4] = domain.y[nd3i]
    elemY[5] = domain.y[nd4i]
    elemY[6] = domain.y[nd5i]
    elemY[7] = domain.y[nd6i]
    elemY[8] = domain.y[nd7i]

    elemZ[1] = domain.z[nd0i]
    elemZ[2] = domain.z[nd1i]
    elemZ[3] = domain.z[nd2i]
    elemZ[4] = domain.z[nd3i]
    elemZ[5] = domain.z[nd4i]
    elemZ[6] = domain.z[nd5i]
    elemZ[7] = domain.z[nd6i]
    elemZ[8] = domain.z[nd7i]

end
function voluDer(x0, x1, x2,
                   x3, x4, x5,
                   y0, y1, y2,
                   y3, y4, y5,
                   z0, z1, z2,
                   z3, z4, z5,
                   dvdx, dvdy, dvdz )

    twelfth = 1.0 / 12.0

    dvdx =
        (y1 + y2) * (z0 + z1) - (y0 + y1) * (z1 + z2) +
        (y0 + y4) * (z3 + z4) - (y3 + y4) * (z0 + z4) -
        (y2 + y5) * (z3 + z5) + (y3 + y5) * (z2 + z5)

    dvdy =
        - (x1 + x2) * (z0 + z1) + (x0 + x1) * (z1 + z2) -
        (x0 + x4) * (z3 + z4) + (x3 + x4) * (z0 + z4) +
        (x2 + x5) * (z3 + z5) - (x3 + x5) * (z2 + z5)

    dvdz =
        - (y1 + y2) * (x0 + x1) + (y0 + y1) * (x1 + x2) -
        (y0 + y4) * (x3 + x4) + (y3 + y4) * (x0 + x4) +
        (y2 + y5) * (x3 + x5) - (y3 + y5) * (x2 + x5)

    dvdx = dvdx * twelfth
    dvdy = dvdy * twelfth
    dvdz = dvdz * twelfth
end

function calcElemVolumeDerivative(dvdx,dvdy,dvdz, x, y, z)

    voluDer(x[2], x[3], x[4], x[5], x[6], x[8],
                y[2], y[3], y[4], y[5], y[6], y[8],
                z[2], z[3], z[4], z[5], z[6], z[8],
                dvdx[1], dvdy[1], dvdz[1])
    voluDer(x[1], x[2], x[3], x[8], x[5], x[7],
                y[1], y[2], y[3], y[8], y[5], y[7],
                z[1], z[2], z[3], z[8], z[5], z[7],
                dvdx[4], dvdy[4], dvdz[4])
    voluDer(x[4], x[1], x[2], x[7], x[8], x[6],
                y[4], y[1], y[2], y[7], y[8], y[6],
                z[4], z[1], z[2], z[7], z[8], z[6],
                dvdx[3], dvdy[3], dvdz[3])
    voluDer(x[3], x[4], x[1], x[6], x[7], x[5],
                y[3], y[4], y[1], y[6], y[7], y[5],
                z[3], z[4], z[1], z[6], z[7], z[5],
                dvdx[2], dvdy[2], dvdz[2])
    voluDer(x[8], x[7], x[6], x[1], x[4], x[2],
                y[8], y[7], y[6], y[1], y[4], y[2],
                z[8], z[7], z[6], z[1], z[4], z[2],
                dvdx[5], dvdy[5], dvdz[5])
    voluDer(x[5], x[8], x[7], x[2], x[1], x[3],
                y[5], y[8], y[7], y[2], y[1], y[3],
                z[5], z[8], z[7], z[2], z[1], z[3],
                dvdx[6], dvdy[6], dvdz[6])
    voluDer(x[6], x[5], x[8], x[3], x[2], x[4],
                y[6], y[5], y[8], y[3], y[2], y[4],
                z[6], z[5], z[8], z[3], z[2], z[4],
                dvdx[7], dvdy[7], dvdz[7])
    voluDer(x[7], x[6], x[5], x[4], x[3], x[1],
                y[7], y[6], y[5], y[4], y[3], y[1],
                z[7], z[6], z[5], z[4], z[3], z[1],
                dvdx[8], dvdy[8], dvdz[8])
end

function calcElemFBHourglassForce(xd, yd, zd,
                                    hourgam0, hourgam1,
                                    hourgam2, hourgam3,
                                    hourgam4, hourgam5,
                                    hourgam6, hourgam7,
                                    coefficient, hgfx,
                                    hgfy, hgfz          )

  i00 = 1
  i01 = 2
  i02 = 3
  i03 = 4


  h00 = (
    hourgam0[i00] * xd[1] + hourgam1[i00] * xd[2] +
    hourgam2[i00] * xd[3] + hourgam3[i00] * xd[4] +
    hourgam4[i00] * xd[5] + hourgam5[i00] * xd[6] +
    hourgam6[i00] * xd[7] + hourgam7[i00] * xd[8]
  )

  h01 = (
    hourgam0[i01] * xd[1] + hourgam1[i01] * xd[2] +
    hourgam2[i01] * xd[3] + hourgam3[i01] * xd[4] +
    hourgam4[i01] * xd[5] + hourgam5[i01] * xd[6] +
    hourgam6[i01] * xd[7] + hourgam7[i01] * xd[8]
  )

  h02 = (
    hourgam0[i02] * xd[1] + hourgam1[i02] * xd[2] +
    hourgam2[i02] * xd[3] + hourgam3[i02] * xd[4] +
    hourgam4[i02] * xd[5] + hourgam5[i02] * xd[6] +
    hourgam6[i02] * xd[7] + hourgam7[i02] * xd[8]
  )

  h03 = (
    hourgam0[i03] * xd[1] + hourgam1[i03] * xd[2] +
    hourgam2[i03] * xd[3] + hourgam3[i03] * xd[4] +
    hourgam4[i03] * xd[5] + hourgam5[i03] * xd[6] +
    hourgam6[i03] * xd[7] + hourgam7[i03] * xd[8]
  )

  hgfx[1] = coefficient *
   (hourgam0[i00] * h00 + hourgam0[i01] * h01 +
    hourgam0[i02] * h02 + hourgam0[i03] * h03)

  hgfx[2] = coefficient *
   (hourgam1[i00] * h00 + hourgam1[i01] * h01 +
    hourgam1[i02] * h02 + hourgam1[i03] * h03)

  hgfx[3] = coefficient *
   (hourgam2[i00] * h00 + hourgam2[i01] * h01 +
    hourgam2[i02] * h02 + hourgam2[i03] * h03)

  hgfx[4] = coefficient *
   (hourgam3[i00] * h00 + hourgam3[i01] * h01 +
    hourgam3[i02] * h02 + hourgam3[i03] * h03)

  hgfx[5] = coefficient *
   (hourgam4[i00] * h00 + hourgam4[i01] * h01 +
    hourgam4[i02] * h02 + hourgam4[i03] * h03)

  hgfx[6] = coefficient *
   (hourgam5[i00] * h00 + hourgam5[i01] * h01 +
    hourgam5[i02] * h02 + hourgam5[i03] * h03)

  hgfx[7] = coefficient *
   (hourgam6[i00] * h00 + hourgam6[i01] * h01 +
    hourgam6[i02] * h02 + hourgam6[i03] * h03)

  hgfx[8] = coefficient *
   (hourgam7[i00] * h00 + hourgam7[i01] * h01 +
    hourgam7[i02] * h02 + hourgam7[i03] * h03)

  h00 = (
    hourgam0[i00] * yd[1] + hourgam1[i00] * yd[2] +
    hourgam2[i00] * yd[3] + hourgam3[i00] * yd[4] +
    hourgam4[i00] * yd[5] + hourgam5[i00] * yd[6] +
    hourgam6[i00] * yd[7] + hourgam7[i00] * yd[8]
  )

  h01 = (
    hourgam0[i01] * yd[1] + hourgam1[i01] * yd[2] +
    hourgam2[i01] * yd[3] + hourgam3[i01] * yd[4] +
    hourgam4[i01] * yd[5] + hourgam5[i01] * yd[6] +
    hourgam6[i01] * yd[7] + hourgam7[i01] * yd[8]
  )

  h02 = (
    hourgam0[i02] * yd[1] + hourgam1[i02] * yd[2]+
    hourgam2[i02] * yd[3] + hourgam3[i02] * yd[4]+
    hourgam4[i02] * yd[5] + hourgam5[i02] * yd[6]+
    hourgam6[i02] * yd[7] + hourgam7[i02] * yd[8]
  )

  h03 = (
    hourgam0[i03] * yd[1] + hourgam1[i03] * yd[2] +
    hourgam2[i03] * yd[3] + hourgam3[i03] * yd[4] +
    hourgam4[i03] * yd[5] + hourgam5[i03] * yd[6] +
    hourgam6[i03] * yd[7] + hourgam7[i03] * yd[8]
  )


  hgfy[1] = coefficient *
   (hourgam0[i00] * h00 + hourgam0[i01] * h01 +
    hourgam0[i02] * h02 + hourgam0[i03] * h03)

  hgfy[2] = coefficient *
   (hourgam1[i00] * h00 + hourgam1[i01] * h01 +
    hourgam1[i02] * h02 + hourgam1[i03] * h03)

  hgfy[3] = coefficient *
   (hourgam2[i00] * h00 + hourgam2[i01] * h01 +
    hourgam2[i02] * h02 + hourgam2[i03] * h03)

  hgfy[4] = coefficient *
   (hourgam3[i00] * h00 + hourgam3[i01] * h01 +
    hourgam3[i02] * h02 + hourgam3[i03] * h03)

  hgfy[5] = coefficient *
   (hourgam4[i00] * h00 + hourgam4[i01] * h01 +
    hourgam4[i02] * h02 + hourgam4[i03] * h03)

  hgfy[6] = coefficient *
   (hourgam5[i00] * h00 + hourgam5[i01] * h01 +
    hourgam5[i02] * h02 + hourgam5[i03] * h03)

  hgfy[7] = coefficient *
   (hourgam6[i00] * h00 + hourgam6[i01] * h01 +
    hourgam6[i02] * h02 + hourgam6[i03] * h03)

  hgfy[8] = coefficient *
   (hourgam7[i00] * h00 + hourgam7[i01] * h01 +
    hourgam7[i02] * h02 + hourgam7[i03] * h03)

  h00 = (
    hourgam0[i00] * zd[1] + hourgam1[i00] * zd[2] +
    hourgam2[i00] * zd[3] + hourgam3[i00] * zd[4] +
    hourgam4[i00] * zd[5] + hourgam5[i00] * zd[6] +
    hourgam6[i00] * zd[7] + hourgam7[i00] * zd[8]
  )

  h01 = (
    hourgam0[i01] * zd[1] + hourgam1[i01] * zd[2] +
    hourgam2[i01] * zd[3] + hourgam3[i01] * zd[4] +
    hourgam4[i01] * zd[5] + hourgam5[i01] * zd[6] +
    hourgam6[i01] * zd[7] + hourgam7[i01] * zd[8]
  )

  h02 =(
    hourgam0[i02] * zd[1] + hourgam1[i02] * zd[2]+
    hourgam2[i02] * zd[3] + hourgam3[i02] * zd[4]+
    hourgam4[i02] * zd[5] + hourgam5[i02] * zd[6]+
    hourgam6[i02] * zd[7] + hourgam7[i02] * zd[8]
  )

  h03 = (
    hourgam0[i03] * zd[1] + hourgam1[i03] * zd[2] +
    hourgam2[i03] * zd[3] + hourgam3[i03] * zd[4] +
    hourgam4[i03] * zd[5] + hourgam5[i03] * zd[6] +
    hourgam6[i03] * zd[7] + hourgam7[i03] * zd[8]
  )


  hgfz[1] = coefficient *
   (hourgam0[i00] * h00 + hourgam0[i01] * h01 +
    hourgam0[i02] * h02 + hourgam0[i03] * h03)

  hgfz[2] = coefficient *
   (hourgam1[i00] * h00 + hourgam1[i01] * h01 +
    hourgam1[i02] * h02 + hourgam1[i03] * h03)

  hgfz[3] = coefficient *
   (hourgam2[i00] * h00 + hourgam2[i01] * h01 +
    hourgam2[i02] * h02 + hourgam2[i03] * h03)

  hgfz[4] = coefficient *
   (hourgam3[i00] * h00 + hourgam3[i01] * h01 +
    hourgam3[i02] * h02 + hourgam3[i03] * h03)

  hgfz[5] = coefficient *
   (hourgam4[i00] * h00 + hourgam4[i01] * h01 +
    hourgam4[i02] * h02 + hourgam4[i03] * h03)

  hgfz[6] = coefficient *
   (hourgam5[i00] * h00 + hourgam5[i01] * h01 +
    hourgam5[i02] * h02 + hourgam5[i03] * h03)

  hgfz[7] = coefficient *
   (hourgam6[i00] * h00 + hourgam6[i01] * h01 +
    hourgam6[i02] * h02 + hourgam6[i03] * h03)

  hgfz[8] = coefficient *
   (hourgam7[i00] * h00 + hourgam7[i01] * h01 +
    hourgam7[i02] * h02 + hourgam7[i03] * h03)
end

function calcFBHourglassForceForElems(domain, determ,
                                        x8n, y8n, z8n,
                                        dvdx, dvdy, dvdz,
                                        hourg             )

    # *************************************************
    # *
    # *     FUNCTION: Calculates the Flanagan-Belytschko anti-hourglass
    # *               force.
    # *
    # *************************************************

    gamma = Matrix{Float64}(undef, 8, 4)

    numElem = domain.numElem
    numElem8 = numElem * 8

    fx_elem = Vector{Float64}(undef, numElem8)
    fy_elem = Vector{Float64}(undef, numElem8)
    fz_elem = Vector{Float64}(undef, numElem8)

    hgfx = Vector{Float64}(undef, 8)
    hgfy = Vector{Float64}(undef, 8)
    hgfz = Vector{Float64}(undef, 8)

    hgfx = Vector{Float64}(undef, 8)
    xd1 = Vector{Float64}(undef, 8)
    yd1 = Vector{Float64}(undef, 8)
    zd1 = Vector{Float64}(undef, 8)

    hourgam0 = Vector{Float64}(undef, 4)
    hourgam1 = Vector{Float64}(undef, 4)
    hourgam2 = Vector{Float64}(undef, 4)
    hourgam3 = Vector{Float64}(undef, 4)
    hourgam4 = Vector{Float64}(undef, 4)
    hourgam5 = Vector{Float64}(undef, 4)
    hourgam6 = Vector{Float64}(undef, 4)
    hourgam7 = Vector{Float64}(undef, 4)

    gamma[1,1] =  1.0
    gamma[2,1] =  1.0
    gamma[3,1] = -1.0
    gamma[4,1] = -1.0
    gamma[5,1] = -1.0
    gamma[6,1] = -1.0
    gamma[7,1] =  1.0
    gamma[8,1] =  1.0
    gamma[1,2] =  1.0
    gamma[2,2] = -1.0
    gamma[3,2] = -1.0
    gamma[4,2] =  1.0
    gamma[5,2] = -1.0
    gamma[6,2] =  1.0
    gamma[7,2] =  1.0
    gamma[8,2] = -1.0
    gamma[1,3] =  1.0
    gamma[2,3] = -1.0
    gamma[3,3] =  1.0
    gamma[4,3] = -1.0
    gamma[5,3] =  1.0
    gamma[6,3] = -1.0
    gamma[7,3] =  1.0
    gamma[8,3] = -1.0
    gamma[1,4] = -1.0
    gamma[2,4] =  1.0
    gamma[3,4] = -1.0
    gamma[4,4] =  1.0
    gamma[5,4] =  1.0
    gamma[6,4] = -1.0
    gamma[7,4] =  1.0
    gamma[8,4] = -1.0

    # *************************************************
    # compute the hourglass modes


    for i2 in 1:numElem

        i3=8*(i2-1)+1
        volinv= 1.0/determ[i2]

        for i1 in 1:4

            hourmodx =
                x8n[i3]   * gamma[1,i1] + x8n[i3+1] * gamma[2,i1] +
                x8n[i3+2] * gamma[3,i1] + x8n[i3+3] * gamma[4,i1] +
                x8n[i3+4] * gamma[5,i1] + x8n[i3+5] * gamma[6,i1] +
                x8n[i3+6] * gamma[7,i1] + x8n[i3+7] * gamma[8,i1]

            hourmody =
                y8n[i3]   * gamma[1,i1] + y8n[i3+1] * gamma[2,i1] +
                y8n[i3+2] * gamma[3,i1] + y8n[i3+3] * gamma[4,i1] +
                y8n[i3+4] * gamma[5,i1] + y8n[i3+5] * gamma[6,i1] +
                y8n[i3+6] * gamma[7,i1] + y8n[i3+7] * gamma[8,i1]

            hourmodz =
                z8n[i3]   * gamma[1,i1] + z8n[i3+1] * gamma[2,i1] +
                z8n[i3+2] * gamma[3,i1] + z8n[i3+3] * gamma[4,i1] +
                z8n[i3+4] * gamma[5,i1] + z8n[i3+5] * gamma[6,i1] +
                z8n[i3+6] * gamma[7,i1] + z8n[i3+7] * gamma[8,i1]

            hourgam0[i1] = gamma[1,i1] -  volinv*(dvdx[i3  ] * hourmodx +
                            dvdy[i3  ] * hourmody + dvdz[i3  ] * hourmodz )

            hourgam1[i1] = gamma[2,i1] -  volinv*(dvdx[i3+1] * hourmodx +
                            dvdy[i3+1] * hourmody + dvdz[i3+1] * hourmodz )

            hourgam2[i1] = gamma[3,i1] -  volinv*(dvdx[i3+2] * hourmodx +
                            dvdy[i3+2] * hourmody + dvdz[i3+2] * hourmodz )

            hourgam3[i1] = gamma[4,i1] -  volinv*(dvdx[i3+3] * hourmodx +
                            dvdy[i3+3] * hourmody + dvdz[i3+3] * hourmodz )

            hourgam4[i1] = gamma[5,i1] -  volinv*(dvdx[i3+4] * hourmodx +
                            dvdy[i3+4] * hourmody + dvdz[i3+4] * hourmodz )

            hourgam5[i1] = gamma[6,i1] -  volinv*(dvdx[i3+5] * hourmodx +
                            dvdy[i3+5] * hourmody + dvdz[i3+5] * hourmodz )

            hourgam6[i1] = gamma[7,i1] -  volinv*(dvdx[i3+6] * hourmodx +
                            dvdy[i3+6] * hourmody + dvdz[i3+6] * hourmodz )

            hourgam7[i1] = gamma[8,i1] -  volinv*(dvdx[i3+7] * hourmodx +
                            dvdy[i3+7] * hourmody + dvdz[i3+7] * hourmodz )
        end


        #   compute forces
        #   store forces into h arrays (force arrays)

        ss1 = domain.ss[i2]
        mass1 = domain.elemMass[i2]
        volume13=cbrt(determ[i2])

        n0si2 = domain.nodelist[(i2-1)*8+1]
        n1si2 = domain.nodelist[(i2-1)*8+2]
        n2si2 = domain.nodelist[(i2-1)*8+3]
        n3si2 = domain.nodelist[(i2-1)*8+4]
        n4si2 = domain.nodelist[(i2-1)*8+5]
        n5si2 = domain.nodelist[(i2-1)*8+6]
        n6si2 = domain.nodelist[(i2-1)*8+7]
        n7si2 = domain.nodelist[(i2-1)*8+8]

        xd1[1] = domain.xd[n0si2]
        xd1[2] = domain.xd[n1si2]
        xd1[3] = domain.xd[n2si2]
        xd1[4] = domain.xd[n3si2]
        xd1[5] = domain.xd[n4si2]
        xd1[6] = domain.xd[n5si2]
        xd1[7] = domain.xd[n6si2]
        xd1[8] = domain.xd[n7si2]

        yd1[1] = domain.yd[n0si2]
        yd1[2] = domain.yd[n1si2]
        yd1[3] = domain.yd[n2si2]
        yd1[4] = domain.yd[n3si2]
        yd1[5] = domain.yd[n4si2]
        yd1[6] = domain.yd[n5si2]
        yd1[7] = domain.yd[n6si2]
        yd1[8] = domain.yd[n7si2]

        zd1[1] = domain.zd[n0si2]
        zd1[2] = domain.zd[n1si2]
        zd1[3] = domain.zd[n2si2]
        zd1[4] = domain.zd[n3si2]
        zd1[5] = domain.zd[n4si2]
        zd1[6] = domain.zd[n5si2]
        zd1[7] = domain.zd[n6si2]
        zd1[8] = domain.zd[n7si2]

        coefficient = - hourg * 0.01 * ss1 * mass1 / volume13

        calcElemFBHourglassForce(xd1,yd1,zd1,
                                    hourgam0,hourgam1,hourgam2,hourgam3,
                                    hourgam4,hourgam5,hourgam6,hourgam7,
                                    coefficient, hgfx, hgfy, hgfz)

        fx_elem[i3] = hgfx[1]
        fx_elem[i3+1] = hgfx[2]
        fx_elem[i3+2] = hgfx[3]
        fx_elem[i3+3] = hgfx[4]
        fx_elem[i3+4] = hgfx[5]
        fx_elem[i3+5] = hgfx[6]
        fx_elem[i3+6] = hgfx[7]
        fx_elem[i3+7] = hgfx[8]

        fy_elem[i3] = hgfy[1]
        fy_elem[i3+1] = hgfy[2]
        fy_elem[i3+2] = hgfy[3]
        fy_elem[i3+3] = hgfy[4]
        fy_elem[i3+4] = hgfy[5]
        fy_elem[i3+5] = hgfy[6]
        fy_elem[i3+6] = hgfy[7]
        fy_elem[i3+7] = hgfy[8]

        fz_elem[i3] = hgfz[1]
        fz_elem[i3+1] = hgfz[2]
        fz_elem[i3+2] = hgfz[3]
        fz_elem[i3+3] = hgfz[4]
        fz_elem[i3+4] = hgfz[5]
        fz_elem[i3+5] = hgfz[6]
        fz_elem[i3+6] = hgfz[7]
        fz_elem[i3+7] = hgfz[8]

    # #if 0
    #     domain%m_fx(n0si2) = domain%m_fx(n0si2) + hgfx(0)
    #     domain%m_fy(n0si2) = domain%m_fy(n0si2) + hgfy(0)
    #     domain%m_fz(n0si2) = domain%m_fz(n0si2) + hgfz(0)

    #     domain%m_fx(n1si2) = domain%m_fx(n1si2) + hgfx(1)
    #     domain%m_fy(n1si2) = domain%m_fy(n1si2) + hgfy(1)
    #     domain%m_fz(n1si2) = domain%m_fz(n1si2) + hgfz(1)

    #     domain%m_fx(n2si2) = domain%m_fx(n2si2) + hgfx(2)
    #     domain%m_fy(n2si2) = domain%m_fy(n2si2) + hgfy(2)
    #     domain%m_fz(n2si2) = domain%m_fz(n2si2) + hgfz(2)

    #     domain%m_fx(n3si2) = domain%m_fx(n3si2) + hgfx(3)
    #     domain%m_fy(n3si2) = domain%m_fy(n3si2) + hgfy(3)
    #     domain%m_fz(n3si2) = domain%m_fz(n3si2) + hgfz(3)

    #     domain%m_fx(n4si2) = domain%m_fx(n4si2) + hgfx(4)
    #     domain%m_fy(n4si2) = domain%m_fy(n4si2) + hgfy(4)
    #     domain%m_fz(n4si2) = domain%m_fz(n4si2) + hgfz(4)

    #     domain%m_fx(n5si2) = domain%m_fx(n5si2) + hgfx(5)
    #     domain%m_fy(n5si2) = domain%m_fy(n5si2) + hgfy(5)
    #     domain%m_fz(n5si2) = domain%m_fz(n5si2) + hgfz(5)

    #     domain%m_fx(n6si2) = domain%m_fx(n6si2) + hgfx(6)
    #     domain%m_fy(n6si2) = domain%m_fy(n6si2) + hgfy(6)
    #     domain%m_fz(n6si2) = domain%m_fz(n6si2) + hgfz(6)

    #     domain%m_fx(n7si2) = domain%m_fx(n7si2) + hgfx(7)
    #     domain%m_fy(n7si2) = domain%m_fy(n7si2) + hgfy(7)
    #     domain%m_fz(n7si2) = domain%m_fz(n7si2) + hgfz(7)
    # #endif
    end

    numNode = domain.numNode

    for gnode in 1:numNode
        count = domain.nodeElemCount[gnode]
        start = domain.nodeElemStart[gnode]
        fx = 0.0
        fy = 0.0
        fz = 0.0
        for i in 1:count
            elem = domain.nodeElemCornerList[start+i]
            fx = fx + fx_elem[elem]
            fy = fy + fy_elem[elem]
            fz = fz + fz_elem[elem]
        end
        domain.fx[gnode] = domain.fx[gnode] + fx
        domain.fy[gnode] = domain.fy[gnode] + fy
        domain.fz[gnode] = domain.fz[gnode] + fz
    end
end

function calcHourglassControlForElems(domain::Domain, determ, hgcoef)
  numElem = domain.numElem
  numElem8 = numElem * 8
  x1 = Vector{Float64}(undef, 8)
  y1 = Vector{Float64}(undef, 8)
  z1 = Vector{Float64}(undef, 8)
  pfx = Vector{Float64}(undef, 8)
  pfy = Vector{Float64}(undef, 8)
  pfz = Vector{Float64}(undef, 8)
  dvdx = Vector{Float64}(undef, numElem8)
  dvdy = Vector{Float64}(0:numElem8)
  dvdz = Vector{Float64}(0:numElem8)
  x8n = Vector{Float64}(0:numElem8)
  y8n = Vector{Float64}(0:numElem8)
  z8n = Vector{Float64}(0:numElem8)

  #start loop over elements
  for i in 1:numElem
    collectDomainNodesToElemNodes(domain, x1, y1, z1, (i-1)*8+1)
    calcElemVolumeDerivative(pfx, pfy, pfz, x1, y1, z1)

    #   load into temporary storage for FB Hour Glass control
    for ii in 1:8
        jj = 8*(i-1) + ii
            dvdx[jj] = pfx[ii]
            dvdy[jj] = pfy[ii]
            dvdz[jj] = pfz[ii]
            x8n[jj]  = x1[ii]
            y8n[jj]  = y1[ii]
            z8n[jj]  = z1[ii]
        end

        determ[i] = domain.volo[i] * domain.v[i]

        #  Do a check for negative volumes
        if domain.v[i] <= 0.0
            error("Volume Error")
        end
    end

    if hgcoef > 0.0
        calcFBHourglassForceForElems(domain, determ,x8n,y8n,z8n,dvdx,dvdy,dvdz,hgcoef)
    end
  return nothing

end

function calcVolumeForceForElems(domain::Domain)
    # Based on FORTRAN implementation down from here
    hgcoef = domain.hgcoef
    numElem = domain.numElem
    VTD = typeof(domain.x)
    sigxx = VTD(undef, numElem)
    sigyy = VTD(undef, numElem)
    sigzz = VTD(undef, numElem)
    determ = VTD(undef, numElem)

    # Sum contributions to total stress tensor
    initStressTermsForElems(domain, sigxx, sigyy, sigzz)

    #   call elemlib stress integration loop to produce nodal forces from
    #   material stresses.
    integrateStressForElems(domain, sigxx, sigyy, sigzz, determ)

    # check for negative element volume and abort if found
    for i in 1:numElem
        if determ[i] <= 0.0
            error("Volume Error")
        end
    end
    calcHourglassControlForElems(domain, determ, hgcoef)
end

function calcForceForNodes(domain::Domain)
    # #if USE_MPI
    #   CommRecv(*domain, MSG_COMM_SBN, 3,
    #            domain->sizeX + 1, domain->sizeY + 1, domain->sizeZ + 1,
    #            true, false) ;
    # #endif
    domain.fx .= 0.0
    domain.fy .= 0.0
    domain.fz .= 0.0

    calcVolumeForceForElems(domain);

    #   moved here from the main loop to allow async execution with GPU work
    # FIXIT not sure this belongs here now
    # TimeIncrement(domain);

end

function calcAccelerationForNodes(domain::Domain)
    domain.xdd .= domain.fx ./ domain.nodalMass
    domain.ydd .= domain.fy ./ domain.nodalMass
    domain.zdd .= domain.fz ./ domain.nodalMass
end

function applyAccelerationBoundaryConditionsForNodes(domain::Domain)

  numNodeBC = (domain.sizeX+1)*(domain.sizeX+1)
  for i in 1:numNodeBC
    domain.xdd[domain.symmX[i]] = 0.0
  end
  for i in 1:numNodeBC
    domain.ydd[domain.symmY[i]] = 0.0
  end
  for i in 1:numNodeBC
    domain.zdd[domain.symmZ[i]] = 0.0
  end
end

function calcVelocityForNodes(domain::Domain, dt, u_cut)


    numNode = domain.numNode

    for i in 1:numNode
        xdtmp = domain.xd[i] + domain.xdd[i] * dt
        if abs(xdtmp) < u_cut
            xdtmp = 0.0
        end
        domain.xd[i] = xdtmp

        ydtmp = domain.yd[i] + domain.ydd[i] * dt
        if abs(ydtmp) < u_cut
            ydtmp = 0.0
        end
        domain.yd[i] = ydtmp

        zdtmp = domain.zd[i] + domain.zdd[i] * dt
        if abs(zdtmp) < u_cut
            zdtmp = 0.0
        end
        domain.zd[i] = zdtmp
    end
end


function calcPositionForNodes(domain::Domain, dt)
    domain.x .= domain.x .+ domain.xd .* dt
    domain.y .= domain.y .+ domain.yd .* dt
    domain.z .= domain.z .+ domain.zd .* dt
end


function lagrangeNodal(domain::Domain)
# #ifdef SEDOV_SYNC_POS_VEL_EARLY
#    Domain_member fieldData[6] ;
# #endif
    delt = domain.deltatime_h

    u_cut = domain.u_cut
    # time of boundary condition evaluation is beginning of step for force and
    # acceleration boundary conditions.
    calcForceForNodes(domain)

# #if USE_MPI
# #ifdef SEDOV_SYNC_POS_VEL_EARLY
#    CommRecv(*domain, MSG_SYNC_POS_VEL, 6,
#             domain->sizeX + 1, domain->sizeY + 1, domain->sizeZ + 1,
#             false, false) ;
# #endif
# #endif

    calcAccelerationForNodes(domain)

    applyAccelerationBoundaryConditionsForNodes(domain)

    calcVelocityForNodes(domain, delt, u_cut)
    calcPositionForNodes(domain, delt)

# #if USE_MPI
# #ifdef SEDOV_SYNC_POS_VEL_EARLY
#   // initialize pointers
#   domain->d_x = domain->x.raw();
#   domain->d_y = domain->y.raw();
#   domain->d_z = domain->z.raw();

#   domain->d_xd = domain->xd.raw();
#   domain->d_yd = domain->yd.raw();
#   domain->d_zd = domain->zd.raw();

#   fieldData[0] = &Domain::get_x ;
#   fieldData[1] = &Domain::get_y ;
#   fieldData[2] = &Domain::get_z ;
#   fieldData[3] = &Domain::get_xd ;
#   fieldData[4] = &Domain::get_yd ;
#   fieldData[5] = &Domain::get_zd ;

#   CommSendGpu(*domain, MSG_SYNC_POS_VEL, 6, fieldData,
#            domain->sizeX + 1, domain->sizeY + 1, domain->sizeZ + 1,
#            false, false, domain->streams[2]) ;
#   CommSyncPosVelGpu(*domain, &domain->streams[2]) ;
# #endif
# #endif
    return nothing
end



function lagrangeLeapFrog(domain::Domain)

   # calculate nodal forces, accelerations, velocities, positions, with
   # applied boundary conditions and slide surface considerations */
   lagrangeNodal(domain)

   # calculate element quantities (i.e. velocity gradient & q), and update
   # material states */
   # LagrangeElements(domain)

   # CalcTimeConstraintsForElems(domain)
   return nothing
end