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

function allocateElemPersistent!(domain, domElems, padded_domElems)
    resize!(domain.matElemlist, domElems) ;  # material indexset
    resize!(domain.nodelist, 8*padded_domElems) ;   # elemToNode connectivity

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

function buildMesh!(domain, nx, edgeNodes, edgeElems, domNodes, padded_domElems, x_h, y_h, z_h, nodelist_h)
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

    resize!(nodelist_h, padded_domElems*8);

    # embed hexehedral elements in nodal point lattice
    # INDEXING
    zidx::IndexT = 1
    nidx = 1
    for plane in 1:edgeElems
        for row in 1:edgeElems
            for col in 1:edgeElems
                nodelist_h[0*padded_domElems+zidx] = nidx
                nodelist_h[1*padded_domElems+zidx] = nidx                                   + 1
                nodelist_h[2*padded_domElems+zidx] = nidx                       + edgeNodes + 1
                nodelist_h[3*padded_domElems+zidx] = nidx                       + edgeNodes
                nodelist_h[4*padded_domElems+zidx] = nidx + edgeNodes*edgeNodes
                nodelist_h[5*padded_domElems+zidx] = nidx + edgeNodes*edgeNodes             + 1
                nodelist_h[6*padded_domElems+zidx] = nidx + edgeNodes*edgeNodes + edgeNodes + 1
                nodelist_h[7*padded_domElems+zidx] = nidx + edgeNodes*edgeNodes + edgeNodes
                zidx+=1
                nidx+=1
            end
        nidx+=1
        end
    nidx+=edgeNodes
    end
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

function sortRegions(domain::Domain, regReps_h::Vector{IndexT}, regSorted_h::Vector{IndexT})
    regIndex = [v for v in 1:domain.numReg]::Vector{IndexT}

    for i in 1:domain.numReg-1
        for j in 1:domain.numReg-i-1
            if regReps_h[j] < regReps_h[j+1]
                temp = regReps_h[j]
                regReps_h[j] = regReps_h[j+1]
                regReps_h[j+1] = temp

                temp = domain.regElemSize[j]
                domain.regElemSize[j] = domain.regElemSize[j+1]
                domain.regElemSize[j+1] = temp

                temp = domain.regIndex[j]
                regIndex[j] = regIndex[j+1]
                regIndex[j+1] = temp
            end
        end
    end
    for i in 1:domain.numReg
        regSorted_h[domain.regIndex[i]] = i
    end
end

function createRegionIndexSets!(domain::Domain, nr::Int, b::Int, comm::MPI.Comm)
    @unpack_Domain domain
    myRank = getMyRank(comm)
    Random.seed!(myRank)
    numReg = nr
    balance = b
    @show numReg
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
            regNumList_h[nextIndex] = 1
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

    sortRegions(domain, regReps_h, regSorted_h);

    regCSR_h[1] = 0;
    # Second, allocate each region index set
    for i in 2:numReg
        regCSR_h[i] = regCSR_h[i-1] + regElemSize[i-1];
    end

    # Third, fill index sets
    for i in 1:numElem
        # INDEXING
        r = regSorted_h[regNumList_h[i]] # region index == regnum-1
        # regElemlist_h[regCSR_h[r]] = i
        regElemlist_h[regCSR_h[r+1]+1] = i
        regCSR_h[r+1] += 1
    end

    # Copy to device
    copyto!(regCSR, regCSR_h) # records the begining and end of each region
    copyto!(regReps, regReps_h) # records the rep number per region
    copyto!(regNumList, regNumList_h) # Region number per domain element
    copyto!(regElemlist, regElemlist_h) # region indexset
    copyto!(regSorted, regSorted_h) # keeps index of sorted regions
    @unpack_Domain domain
end

function NewDomain(prob::LuleshProblem)
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
        0,0,
        0,0,
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
        domain.padded_numElem = PAD(domain.numElem,32);

        domain.numNode = (domain.sizeX+1)*(domain.sizeY+1)*(domain.sizeZ+1)
        domain.padded_numNode = PAD(domain.numNode,32);

        domElems = domain.numElem
        domNodes = domain.numNode
        padded_domElems = domain.padded_numElem

        # Build domain object here. Not nice.


        allocateElemPersistent!(domain, domElems, padded_domElems);
        allocateNodalPersistent!(domain, domNodes);

    #     domain->SetupCommBuffers(edgeNodes);

        initializeFields!(domain)

        buildMesh!(domain, nx, edgeNodes, edgeElems, domNodes, padded_domElems, x_h, y_h, z_h, nodelist_h)

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
            nodeElemCount_h[nodelist_h[j*padded_domElems+i]]+=1
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
            m = nodelist_h[padded_domElems*j+i]
            k = padded_domElems*j + i
            # INDEXING
            offset = nodeElemStart_h[m] + nodeElemCount_h[m]
            nodeElemCornerList_h[offset+1] = k
            nodeElemCount_h[m] += 1
        end
    end

    clSize = nodeElemStart_h[domNodes] + nodeElemCount_h[domNodes]
    for i in 1:clSize
        clv = nodeElemCornerList_h[i] ;
        if (clv < 0) || (clv > padded_domElems*8)
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
            gnode = nodelist_h[lnode*padded_domElems+i]
            x_local[lnode+1] = x_h[gnode]
            y_local[lnode+1] = y_h[gnode]
            z_local[lnode+1] = z_h[gnode]
        end
        # volume calculations
        volume = calcElemVolume(x_local, y_local, z_local )
        volo_h[i] = volume
        elemMass_h[i] = volume
        for j in 0:7
            gnode = nodelist_h[j*padded_domElems+i]
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
    return nothing
end